#!/usr/bin/env python3
"""Probe SCMUtils sources for likely LispPad/LispKit blockers.

This scanner defaults to the vendored SCMUtils bundle at
`/Volumes/GitHubDeveloper/Packages/SCMUtilsBundle`, but it accepts any
compatible checkout. In addition to the source-level compatibility scan, it
summarizes the install chain driven by `install.sh`:

  install.sh -> system-library-directory-pathname/scmutils/*.bci
             -> system-library-directory-pathname/mechanics.com

That install path is useful context because it shows which artifacts are
MIT-Scheme-specific binaries and which entry points remain source-based.
"""

from __future__ import annotations

import argparse
import json
import os
import re
from dataclasses import dataclass
import subprocess
import tempfile
import sys
from typing import Dict, List, Set, Tuple


SCMUTILS_BUNDLE_ROOT = "/Volumes/GitHubDeveloper/Packages/SCMUtilsBundle"
DEFAULT_ROOT = SCMUTILS_BUNDLE_ROOT + "/LispKit/scmutils-20230902"
DEFAULT_LISPKIT_REPL = "/Volumes/GitHubDeveloper/Packages/swift-lispkit/.build/debug/LispKitRepl"
DEFAULT_LISPKIT_RESOURCES = "/Volumes/GitHubDeveloper/Packages/swift-lispkit/Sources/LispKit/Resources"
DEFAULT_BOOTSTRAP = SCMUTILS_BUNDLE_ROOT + "/Bootstrap/scmutils_lispkit_bootstrap.scm"
SEVERITY_ORDER = {"S1": 0, "S2": 1, "S3": 2}


@dataclass(frozen=True)
class Rule:
    rule_id: str
    severity: str
    title: str
    description: str
    pattern: re.Pattern[str]


RULES: List[Rule] = [
    Rule(
        "mit_lambda_keywords",
        "S1",
        "MIT Lambda Keywords",
        "MIT Scheme lambda list keywords (`#!optional`, `#!rest`, etc.) are not portable.",
        re.compile(r"#!(?:optional|rest|key|aux)\b"),
    ),
    Rule(
        "mit_environment_api",
        "S1",
        "MIT Environment API",
        "MIT runtime environment APIs (`access`, `->environment`, `environment-define`, etc.) are non-portable.",
        re.compile(
            r"\((?:access|->environment|environment-define|environment-link-name|"
            r"environment-bound\?|environment-lookup|extend-top-level-environment|"
            r"local-assignment)\b"
        ),
    ),
    Rule(
        "mit_loader_path_api",
        "S1",
        "MIT Loader/Path API",
        "MIT loader/path APIs (`with-directory-rewriting-rule`, `pathname-*`, `current-load-pathname`) are non-portable.",
        re.compile(
            r"\b(?:with-directory-rewriting-rule|with-working-directory-pathname|"
            r"current-load-pathname|merge-pathnames|directory-pathname|"
            r"pathname-[A-Za-z0-9\-]+|except-last-pair)\b"
        ),
    ),
    Rule(
        "mit_runtime_globals",
        "S1",
        "MIT Runtime Globals",
        "References to MIT runtime globals (`user-initial-environment`, `system-global-environment`, etc.).",
        re.compile(
            r"\b(?:user-initial-environment|system-global-environment|"
            r"user-generic-environment|generic-environment|symbolic-environment|"
            r"rule-environment)\b"
        ),
    ),
    Rule(
        "mit_bootstrap_forms",
        "S1",
        "MIT Bootstrap Forms",
        "MIT bootstrap helpers (`ge`, `load-option`, case-mode toggles) are not standard Scheme.",
        re.compile(
            r"\((?:ge|load-option|start-canonicalizing-symbols!?|"
            r"start-preserving-case!|add-subsystem-identification!)\b"
        ),
    ),
    Rule(
        "mit_load_environment",
        "S1",
        "MIT `load` Environment Argument",
        "SCMUtils often calls `load` with an explicit environment argument, which is not portable to LispKit.",
        re.compile(r'\(load\s+"[^"]+"\s+[A-Za-z0-9:\-\*?!]+\)'),
    ),
    Rule(
        "declare_form",
        "S2",
        "Declare Form",
        "`(declare ...)` is implementation-specific and usually ignored or rejected outside MIT Scheme.",
        re.compile(r"^\s*\(declare\b", re.MULTILINE),
    ),
    Rule(
        "fluid_let",
        "S2",
        "Fluid Let",
        "`fluid-let` is not part of R5RS/R7RS base and needs emulation.",
        re.compile(r"\(fluid-let\b"),
    ),
    Rule(
        "compiler_controls",
        "S2",
        "Compiler Control Vars",
        "Compiler control references (`compiler:*`) are implementation-specific.",
        re.compile(r"\bcompiler:[A-Za-z0-9_\-\?\!]+\b"),
    ),
    Rule(
        "system_level_io",
        "S3",
        "System/Graphics Integration",
        "Potential host runtime dependencies (X graphics hooks, subprocess hooks, etc.).",
        re.compile(
            r"\b(?:x-graphics|x11|x11-screen|synchronous-subprocess|"
            r"compile-and-run-sexp|runtime)\b"
        ),
    ),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Scan SCMUtils sources for MIT-Scheme-specific constructs."
    )
    parser.add_argument(
        "root",
        nargs="?",
        default=DEFAULT_ROOT,
        help=f"Root directory to scan (default: {DEFAULT_ROOT}).",
    )
    parser.add_argument(
        "--extensions",
        default=".scm",
        help="Comma-separated file extensions to include in the source scan (default: .scm).",
    )
    parser.add_argument(
        "--max-examples",
        type=int,
        default=4,
        help="Max examples per rule (default: 4).",
    )
    parser.add_argument(
        "--top-files",
        type=int,
        default=15,
        help="Number of top files by hit count (default: 15).",
    )
    parser.add_argument(
        "--format",
        choices=["text", "json"],
        default="text",
        help="Output format (default: text).",
    )
    parser.add_argument(
        "--output",
        default="",
        help="Optional output file path. Defaults to stdout.",
    )
    parser.add_argument(
        "--runtime-check",
        action="store_true",
        help="Run a few real LispKit loader attempts in addition to the static source scan.",
    )
    parser.add_argument(
        "--lispkit-repl",
        default=DEFAULT_LISPKIT_REPL,
        help=f"Path to LispKitRepl executable (default: {DEFAULT_LISPKIT_REPL}).",
    )
    parser.add_argument(
        "--bootstrap",
        default=DEFAULT_BOOTSTRAP,
        help=f"Path to the LispKit-oriented SCMUtils bootstrap script (default: {DEFAULT_BOOTSTRAP}).",
    )
    parser.add_argument(
        "--lispkit-resources",
        default=DEFAULT_LISPKIT_RESOURCES,
        help=f"Path to LispKit resource root (default: {DEFAULT_LISPKIT_RESOURCES}).",
    )
    return parser.parse_args()


def is_target_file(path: str, extensions: Set[str]) -> bool:
    _, ext = os.path.splitext(path)
    return ext.lower() in extensions


def root_skip_dirs(root: str) -> Set[str]:
    skip = {".git", ".hg", ".svn", "target", "build", "__pycache__"}
    basename = os.path.basename(os.path.abspath(root))
    if basename:
        skip.add(basename)
    return skip


def walk_files(root: str, extensions: Set[str]) -> List[str]:
    paths: List[str] = []
    skip_dirs = root_skip_dirs(root)
    for current_root, dirs, files in os.walk(root):
        if os.path.abspath(current_root) == os.path.abspath(root):
            dirs[:] = [d for d in dirs if d not in skip_dirs]
        else:
            dirs[:] = [d for d in dirs if d not in {".git", ".hg", ".svn", "__pycache__"}]
        for name in files:
            path = os.path.join(current_root, name)
            if is_target_file(path, extensions):
                paths.append(path)
    return paths


def collect_files(root: str, suffix: str) -> List[str]:
    matches: List[str] = []
    skip_dirs = root_skip_dirs(root)
    for current_root, dirs, files in os.walk(root):
        if os.path.abspath(current_root) == os.path.abspath(root):
            dirs[:] = [d for d in dirs if d not in skip_dirs]
        else:
            dirs[:] = [d for d in dirs if d not in {".git", ".hg", ".svn", "__pycache__"}]
        for name in files:
            if name.lower().endswith(suffix.lower()):
                matches.append(os.path.join(current_root, name))
    return matches


def strip_line_comments_and_strings(source: str) -> str:
    out: List[str] = []
    in_string = False
    in_comment = False
    escaped = False

    for ch in source:
        if in_comment:
            if ch == "\n":
                in_comment = False
                out.append("\n")
            else:
                out.append(" ")
            continue

        if in_string:
            if escaped:
                escaped = False
                out.append(" ")
            elif ch == "\\":
                escaped = True
                out.append(" ")
            elif ch == '"':
                in_string = False
                out.append('"')
            elif ch == "\n":
                out.append("\n")
            else:
                out.append(" ")
            continue

        if ch == ";":
            in_comment = True
            out.append(" ")
        elif ch == '"':
            in_string = True
            out.append('"')
        else:
            out.append(ch)

    return "".join(out)


def line_info(source: str, pos: int) -> Tuple[int, str]:
    line_no = source.count("\n", 0, pos) + 1
    start = source.rfind("\n", 0, pos) + 1
    end = source.find("\n", pos)
    if end < 0:
        end = len(source)
    snippet = source[start:end].strip()
    if len(snippet) > 180:
        snippet = snippet[:177] + "..."
    return line_no, snippet


def scan(root: str, files: List[str], max_examples: int) -> Dict[str, object]:
    counts: Dict[str, int] = {rule.rule_id: 0 for rule in RULES}
    files_by_rule: Dict[str, Set[str]] = {rule.rule_id: set() for rule in RULES}
    examples: Dict[str, List[Dict[str, object]]] = {rule.rule_id: [] for rule in RULES}
    file_totals: Dict[str, int] = {}
    scan_errors: List[Dict[str, str]] = []

    for path in files:
        relpath = os.path.relpath(path, root)
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                source = fh.read()
        except OSError as exc:
            scan_errors.append({"file": relpath, "error": str(exc)})
            continue

        searchable = strip_line_comments_and_strings(source)
        file_total = 0

        for rule in RULES:
            seen_lines: Set[int] = set()
            for match in rule.pattern.finditer(searchable):
                line_no, snippet = line_info(source, match.start())
                if line_no in seen_lines:
                    continue
                seen_lines.add(line_no)

                counts[rule.rule_id] += 1
                files_by_rule[rule.rule_id].add(relpath)
                file_total += 1

                if len(examples[rule.rule_id]) < max_examples:
                    examples[rule.rule_id].append(
                        {
                            "file": relpath,
                            "line": line_no,
                            "snippet": snippet,
                            "match": match.group(0),
                        }
                    )

        if file_total > 0:
            file_totals[relpath] = file_total

    severity_totals: Dict[str, int] = {"S1": 0, "S2": 0, "S3": 0}
    for rule in RULES:
        severity_totals[rule.severity] += counts[rule.rule_id]

    rules_out: List[Dict[str, object]] = []
    for rule in RULES:
        rules_out.append(
            {
                "rule_id": rule.rule_id,
                "severity": rule.severity,
                "title": rule.title,
                "description": rule.description,
                "count": counts[rule.rule_id],
                "file_count": len(files_by_rule[rule.rule_id]),
                "files": sorted(files_by_rule[rule.rule_id]),
                "examples": examples[rule.rule_id],
            }
        )

    rules_out.sort(
        key=lambda r: (
            SEVERITY_ORDER[r["severity"]],
            -int(r["count"]),
            r["title"],
        )
    )
    top_files = sorted(file_totals.items(), key=lambda kv: (-kv[1], kv[0]))

    return {
        "root": root,
        "scanned_file_count": len(files),
        "severity_totals": severity_totals,
        "rules": rules_out,
        "top_files": [{"file": f, "count": c} for f, c in top_files],
        "scan_errors": scan_errors,
    }


def read_file(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def extract_included_modules(load_real_source: str) -> List[str]:
    pattern = re.compile(r'\(in-scmutils-directory\s+"\.\/([^"]+)"')
    modules = []
    for match in pattern.finditer(load_real_source):
        module = match.group(1)
        if module not in modules:
            modules.append(module)
    return modules


def extract_load_options(load_real_source: str) -> List[str]:
    pattern = re.compile(r"\(load-option\s+'([A-Za-z0-9\-]+)\)")
    options = []
    for match in pattern.finditer(load_real_source):
        option = match.group(1)
        if option not in options:
            options.append(option)
    return options


def build_inventory(root: str) -> Dict[str, object]:
    install_path = os.path.join(root, "install.sh")
    load_path = os.path.join(root, "load.scm")
    load_real_path = os.path.join(root, "load-real.scm")
    mechanics_band_path = os.path.join(root, "mechanics.com")
    mechanics_wrapper_path = os.path.join(root, "mechanics.sh")

    load_real_source = read_file(load_real_path)
    bci_files = collect_files(root, ".bci")

    return {
        "install_script": os.path.isfile(install_path),
        "source_loader": os.path.isfile(load_path),
        "source_loader_real": os.path.isfile(load_real_path),
        "mechanics_band": os.path.isfile(mechanics_band_path),
        "mechanics_wrapper": os.path.isfile(mechanics_wrapper_path),
        "bci_count": len(bci_files),
        "bci_examples": [
            os.path.relpath(path, root) for path in sorted(bci_files)[:6]
        ],
        "load_modules": extract_included_modules(load_real_source),
        "load_options": extract_load_options(load_real_source),
    }


def summarize_process_output(text: str, limit: int = 6) -> List[str]:
    lines = [line.rstrip() for line in text.splitlines() if line.strip()]
    return lines[:limit]


def run_lispkit_probe(command: List[str], cwd: str | None = None) -> Dict[str, object]:
    try:
        completed = subprocess.run(
            command,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=45,
        )
    except subprocess.TimeoutExpired:
        return {
            "status": "timeout",
            "command": command,
            "returncode": None,
            "stdout": [],
            "stderr": ["probe timed out after 45 seconds"],
        }
    except OSError as exc:
        return {
            "status": "error",
            "command": command,
            "returncode": None,
            "stdout": [],
            "stderr": [str(exc)],
        }

    status = "ok" if completed.returncode == 0 else "failed"
    return {
        "status": status,
        "command": command,
        "returncode": completed.returncode,
        "stdout": summarize_process_output(completed.stdout),
        "stderr": summarize_process_output(completed.stderr),
    }


def runtime_inventory(
    root: str,
    lispkit_repl: str,
    lispkit_resources: str,
    bootstrap_path: str,
) -> Dict[str, object]:
    runtime: Dict[str, object] = {
        "enabled": True,
        "lispkit_repl": lispkit_repl,
        "lispkit_resources": lispkit_resources,
        "bootstrap": bootstrap_path,
        "probes": [],
    }

    if not os.path.isfile(lispkit_repl):
        runtime["status"] = "missing_repl"
        runtime["error"] = f"LispKitRepl not found at {lispkit_repl}"
        return runtime
    if not os.path.isdir(lispkit_resources):
        runtime["status"] = "missing_resources"
        runtime["error"] = f"LispKit resources not found at {lispkit_resources}"
        return runtime
    if not os.path.isfile(bootstrap_path):
        runtime["status"] = "missing_bootstrap"
        runtime["error"] = f"bootstrap script not found at {bootstrap_path}"
        return runtime

    base_command = [lispkit_repl, "-r", lispkit_resources, "---"]

    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".scm",
        prefix="scmutils-load-real-",
        delete=False,
        encoding="utf-8",
    ) as handle:
        handle.write(f'(load "{os.path.join(root, "load-real.scm")}")\n')
        load_real_probe_path = handle.name

    try:
        probes = [
            {
                "name": "raw_load_scm",
                "entry": os.path.join(root, "load.scm"),
                "result": run_lispkit_probe(base_command + [os.path.join(root, "load.scm")]),
            },
            {
                "name": "raw_load_real_scm",
                "entry": os.path.join(root, "load-real.scm"),
                "result": run_lispkit_probe(base_command + [load_real_probe_path]),
            },
            {
                "name": "lispkit_bootstrap",
                "entry": bootstrap_path,
                "result": run_lispkit_probe(base_command + [bootstrap_path]),
            },
        ]
    finally:
        try:
            os.unlink(load_real_probe_path)
        except OSError:
            pass

    runtime["status"] = "ok"
    runtime["probes"] = probes
    return runtime


def suggested_steps(result: Dict[str, object], inventory: Dict[str, object]) -> List[str]:
    rule_counts = {rule["rule_id"]: rule["count"] for rule in result["rules"]}
    steps: List[str] = []

    if int(inventory["bci_count"]) > 0 or bool(inventory["mechanics_band"]):
        steps.append(
            "Ignore MIT-installed `.bci` and `mechanics.com` artifacts for LispPad; port from the `.scm` loader chain instead."
        )

    if any(
        int(rule_counts.get(rid, 0))
        for rid in (
            "mit_lambda_keywords",
            "mit_environment_api",
            "mit_loader_path_api",
            "mit_bootstrap_forms",
            "mit_load_environment",
        )
    ):
        steps.append(
            "Replace MIT bootstrap/environment APIs first (`access`, `->environment`, "
            "`environment-define`, `load-option`, `ge`, pathname helpers, environment-style `load`)."
        )

    if int(rule_counts.get("declare_form", 0)):
        steps.append("Strip or translate `(declare ...)` forms before evaluation.")

    if int(rule_counts.get("fluid_let", 0)):
        steps.append("Provide `fluid-let` compatibility or rewrite to parameterization/bindings.")

    if int(rule_counts.get("compiler_controls", 0)):
        steps.append("Remove compiler-control code paths (`compiler:*`) for runtime loading.")

    if int(rule_counts.get("system_level_io", 0)):
        steps.append("Isolate graphics, Edwin, X11, and subprocess integration behind stubs or host adapters.")

    return steps


def render_text(
    result: Dict[str, object],
    inventory: Dict[str, object],
    runtime: Dict[str, object] | None,
    top_files: int,
) -> str:
    lines: List[str] = []
    lines.append(f"SCMUtils compatibility probe root: {result['root']}")
    lines.append(f"Scanned Scheme files: {result['scanned_file_count']}")
    lines.append("")
    lines.append("Install-chain inventory:")
    lines.append(
        "  install.sh copies compiled SCMUtils artifacts into MIT Scheme's "
        "system-library-directory-pathname."
    )
    lines.append(f"  install.sh present: {'yes' if inventory['install_script'] else 'no'}")
    lines.append(f"  source loader present: {'yes' if inventory['source_loader'] else 'no'} (load.scm)")
    lines.append(
        f"  source loader real present: {'yes' if inventory['source_loader_real'] else 'no'} (load-real.scm)"
    )
    lines.append(f"  mechanics.com present: {'yes' if inventory['mechanics_band'] else 'no'}")
    lines.append(f"  mechanics.sh present: {'yes' if inventory['mechanics_wrapper'] else 'no'}")
    lines.append(f"  compiled `.bci` files: {inventory['bci_count']}")
    if inventory["bci_examples"]:
        lines.append("  sample compiled artifacts:")
        for path in inventory["bci_examples"]:
            lines.append(f"    - {path}")
    if inventory["load_options"]:
        lines.append("  MIT load options seen in load-real.scm:")
        for option in inventory["load_options"]:
            lines.append(f"    - {option}")
    if inventory["load_modules"]:
        lines.append("  modules pulled by load-real.scm:")
        for module in inventory["load_modules"]:
            lines.append(f"    - {module}")
    lines.append(f"  LispKit bootstrap script present: {'yes' if os.path.isfile(DEFAULT_BOOTSTRAP) else 'no'}")

    lines.append("")
    lines.append("Severity totals:")
    for sev in ("S1", "S2", "S3"):
        lines.append(f"  {sev}: {result['severity_totals'][sev]}")

    lines.append("")
    lines.append("Rules (sorted by severity then count):")
    any_hits = False
    for rule in result["rules"]:
        if int(rule["count"]) == 0:
            continue
        any_hits = True
        lines.append(
            f"  [{rule['severity']}] {rule['title']}: "
            f"{rule['count']} hits across {rule['file_count']} files"
        )
        lines.append(f"    {rule['description']}")
        for ex in rule["examples"]:
            lines.append(f"    - {ex['file']}:{ex['line']}  {ex['snippet']}")
    if not any_hits:
        lines.append("  No matches found.")

    lines.append("")
    lines.append(f"Top files by hit count (top {top_files}):")
    shown = result["top_files"][:top_files]
    if shown:
        for item in shown:
            lines.append(f"  {item['count']:4d}  {item['file']}")
    else:
        lines.append("  none")

    if result["scan_errors"]:
        lines.append("")
        lines.append("Scan errors:")
        for err in result["scan_errors"]:
            lines.append(f"  {err['file']}: {err['error']}")

    if runtime:
        lines.append("")
        lines.append("Runtime probes:")
        status = runtime.get("status")
        if status != "ok":
            lines.append(f"  unavailable: {runtime.get('error', status)}")
        else:
            lines.append(f"  LispKitRepl: {runtime['lispkit_repl']}")
            lines.append(f"  resources: {runtime['lispkit_resources']}")
            lines.append(f"  bootstrap: {runtime['bootstrap']}")
            for probe in runtime["probes"]:
                result_out = probe["result"]
                lines.append(
                    f"  {probe['name']}: {result_out['status']} "
                    f"(exit={result_out['returncode']})"
                )
                lines.append(f"    entry: {probe['entry']}")
                for line in result_out["stdout"]:
                    lines.append(f"    out: {line}")
                for line in result_out["stderr"]:
                    lines.append(f"    err: {line}")

    lines.append("")
    lines.append("Suggested first transformations:")
    steps = suggested_steps(result, inventory)
    if steps:
        for idx, step in enumerate(steps, start=1):
            lines.append(f"  {idx}. {step}")
    else:
        lines.append("  1. No major incompatibility signatures found by current rule set.")

    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        print(f"error: root is not a directory: {root}", file=sys.stderr)
        return 2

    extensions = {
        ext.strip().lower()
        for ext in args.extensions.split(",")
        if ext.strip()
    }
    if not extensions:
        print("error: no valid extensions configured", file=sys.stderr)
        return 2

    files = walk_files(root, extensions)
    result = scan(root, files, max_examples=max(1, args.max_examples))
    inventory = build_inventory(root)
    runtime = None
    if args.runtime_check:
        runtime = runtime_inventory(
            root,
            os.path.abspath(args.lispkit_repl),
            os.path.abspath(args.lispkit_resources),
            os.path.abspath(args.bootstrap),
        )

    if args.format == "json":
        output = json.dumps(
            {
                "inventory": inventory,
                "scan": result,
                "runtime": runtime,
            },
            indent=2,
            sort_keys=False,
        )
    else:
        output = render_text(result, inventory, runtime, top_files=max(1, args.top_files))

    if args.output:
        out_path = os.path.abspath(args.output)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write(output)
            fh.write("\n")
    else:
        print(output)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
