import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct PythonWorkbenchView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var code = """
import sympy
print(sympy.sqrt(3))
x = sympy.symbols('x')
print(sympy.expand((x+1)**2))
"""
    @State private var result = ""
    @State private var isRunning = false

    private var palette: LabTheme.Palette {
        LabTheme.palette(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Python Workbench")
                .font(.largeTitle.bold())

            Text("This keeps the PyDE-style Python surface inside MorphoVu. On macOS it runs your local `python3` for now; embedded Python can plug into the same UI later.")
                .foregroundStyle(palette.secondaryInk)

            codeEditor
                .frame(minHeight: 240)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(palette.panelElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(palette.keyBorder, lineWidth: 1)
                )
                .shadow(color: palette.softShadow, radius: 10, y: 6)

            HStack(spacing: 12) {
                Button(isRunning ? "Running..." : "Run Python") {
                    runPython()
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .disabled(isRunning)

                Text(platformStatus)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryInk)
            }

            outputPanel
            .frame(minHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(palette.outputPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(palette.keyBorder, lineWidth: 1)
            )
        }
        .padding(24)
        .foregroundStyle(palette.ink)
        .background(
            LinearGradient(
                colors: [
                    palette.shellStart,
                    palette.shellEnd
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    @ViewBuilder
    private var codeEditor: some View {
        #if os(macOS)
        MacPythonTextView(
            text: $code,
            isEditable: true,
            textColor: editorTextColor,
            insertionPointColor: editorTextColor,
            selectionColor: selectionColor
        )
        #else
        TextEditor(text: $code)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(palette.ink)
            .padding(14)
            .hidesEditorScrollBackgroundWhenSupported()
            .pythonTextInputTraits()
        #endif
    }

    @ViewBuilder
    private var outputPanel: some View {
        #if os(macOS)
        MacPythonTextView(
            text: .constant(result.isEmpty ? "Output will appear here." : result),
            isEditable: false,
            textColor: outputTextColor,
            insertionPointColor: outputTextColor,
            selectionColor: selectionColor
        )
        #else
        ScrollView {
            Text(result.isEmpty ? "Output will appear here." : result)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(palette.outputInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        #endif
    }

    private var platformStatus: String {
        #if os(macOS)
        if PythonSupportPaths.discover().appPackages != nil {
            return "Uses local python3 with bundled PyDE app_packages until the embedded runtime lands."
        }
        return "Uses local python3 until the embedded runtime lands."
        #else
        return "UI ready; embedded Python still needs platform wiring."
        #endif
    }

    #if os(macOS)
    private var editorTextColor: NSColor {
        switch colorScheme {
        case .dark:
            NSColor(srgbRed: 0.95, green: 0.97, blue: 0.99, alpha: 1)
        default:
            NSColor(srgbRed: 0.17, green: 0.16, blue: 0.14, alpha: 1)
        }
    }

    private var outputTextColor: NSColor {
        switch colorScheme {
        case .dark:
            NSColor(srgbRed: 0.91, green: 0.94, blue: 0.99, alpha: 1)
        default:
            NSColor(srgbRed: 0.95, green: 0.96, blue: 0.98, alpha: 1)
        }
    }

    private var selectionColor: NSColor {
        NSColor.systemTeal.withAlphaComponent(colorScheme == .dark ? 0.35 : 0.22)
    }
    #endif

    private func runPython() {
        result = ""
        isRunning = true
        let supportPaths = PythonSupportPaths.discover()

        Task {
            let output = await PythonRunner.run(code: code, supportPaths: supportPaths)
            await MainActor.run {
                result = output
                isRunning = false
            }
        }
    }
}

private struct PythonSupportPaths: Sendable {
    let app: String?
    let appPackages: String?

    static func discover(in bundle: Bundle = .main) -> PythonSupportPaths {
        let fileManager = FileManager.default
        let resourceURL = bundle.resourceURL

        func existingDirectory(named name: String) -> String? {
            guard let url = resourceURL?.appendingPathComponent(name, isDirectory: true) else {
                return nil
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }

            return url.path
        }

        return PythonSupportPaths(
            app: existingDirectory(named: "app"),
            appPackages: existingDirectory(named: "app_packages")
        )
    }
}

private enum PythonRunner {
    static func run(code: String, supportPaths: PythonSupportPaths) async -> String {
        #if os(macOS)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runLocalPython(code: code, supportPaths: supportPaths))
            }
        }
        #else
        return "Python execution is not wired into MorphoVu on this platform yet."
        #endif
    }

    #if os(macOS)
    private static func runLocalPython(code: String, supportPaths: PythonSupportPaths) -> String {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = pythonExecutableURL()
        process.arguments = ["-c", bootstrapScript]
        process.environment = pythonEnvironment(for: supportPaths)
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            let stdinHandle = stdinPipe.fileHandleForWriting
            stdinHandle.write(Data(code.utf8))
            try? stdinHandle.close()
            process.waitUntilExit()
        } catch {
            return "Unable to start local python3: \(error.localizedDescription)"
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(decoding: stdoutData, as: UTF8.self)
        let stderr = String(decoding: stderrData, as: UTF8.self)

        if process.terminationStatus == 0 {
            return stdout.isEmpty ? "Python ran successfully with no stdout." : stdout
        }

        let body = stderr.isEmpty ? stdout : stderr
        return body.isEmpty
            ? "python3 exited with status \(process.terminationStatus)."
            : body
    }

    private static var bootstrapScript: String {
        """
        import os
        import site
        import sys

        app_packages = os.environ.get("MORPHOVU_APP_PACKAGES")
        if app_packages and os.path.isdir(app_packages):
            site.addsitedir(app_packages)

        app = os.environ.get("MORPHOVU_APP")
        if app and os.path.isdir(app):
            sys.path.insert(0, app)

        source = sys.stdin.read()
        namespace = {"__name__": "__main__", "__file__": "<MorphoVuPython>"}
        exec(compile(source, "<MorphoVuPython>", "exec"), namespace)
        """
    }

    private static func pythonEnvironment(for supportPaths: PythonSupportPaths) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment

        if let app = supportPaths.app {
            environment["MORPHOVU_APP"] = app
        } else {
            environment.removeValue(forKey: "MORPHOVU_APP")
        }

        if let appPackages = supportPaths.appPackages {
            environment["MORPHOVU_APP_PACKAGES"] = appPackages
        } else {
            environment.removeValue(forKey: "MORPHOVU_APP_PACKAGES")
        }

        return environment
    }

    private static func pythonExecutableURL() -> URL {
        let fileManager = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3.14",
            "/usr/local/bin/python3.14",
            "/usr/bin/python3"
        ]

        if let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }

        return URL(fileURLWithPath: "/usr/bin/python3")
    }
    #endif
}

#if os(macOS)
private struct MacPythonTextView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let textColor: NSColor
    let insertionPointColor: NSColor
    let selectionColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isEditable: isEditable)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize + 1, weight: .regular)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = isEditable
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        updateScrollBehavior(scrollView)
        applyAppearance(to: textView)
        textView.string = text

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
        }

        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = isEditable
        applyAppearance(to: textView)
        updateScrollBehavior(scrollView)
    }

    private func applyAppearance(to textView: NSTextView) {
        textView.textColor = textColor
        textView.insertionPointColor = insertionPointColor
        textView.backgroundColor = .clear
        textView.selectedTextAttributes = [
            .backgroundColor: selectionColor,
            .foregroundColor: textColor
        ]
    }

    private func updateScrollBehavior(_ scrollView: NSScrollView) {
        let preferredStyle = NSScroller.preferredScrollerStyle
        scrollView.scrollerStyle = preferredStyle
        scrollView.autohidesScrollers = preferredStyle != .legacy
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>
        private let isEditable: Bool

        init(text: Binding<String>, isEditable: Bool) {
            self.text = text
            self.isEditable = isEditable
        }

        func textDidChange(_ notification: Notification) {
            guard isEditable,
                  let textView = notification.object as? NSTextView
            else {
                return
            }

            text.wrappedValue = textView.string
        }
    }
}
#endif

#Preview {
    PythonWorkbenchView()
}
