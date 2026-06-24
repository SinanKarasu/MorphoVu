// LineExpressionModel+DrJit.swift
// ─────────────────────────────────────────────────────────────────────────────
// Dr.Jit Metal backend evaluation of LaTeX math expressions.
//
// Unlike the numeric and SymEngine backends (which loop over sample points one
// at a time), this builder walks the ANTLR parse tree once and constructs a
// lazy JITArray computation graph.  drjit-core compiles the graph to a single
// MSL kernel and evaluates all sample points in parallel on the GPU.
//
// Supported ops: +, -, *, /, neg, ^, \sin, \cos, \tan, \exp, \log, \sqrt,
//   fractions, grouping, \pi, numeric literals, identifiers (x, a, b).
//
// pow(base, exp) uses the identity a^b = exp2(log2(a) * b), valid for a > 0.
// For tan: evaluated as sin(x) / cos(x).
// For exp: exp2(x * log₂e).
// For log: log2(x) * ln(2).
// ─────────────────────────────────────────────────────────────────────────────

@preconcurrency import Antlr4
import DrJitKit
import Foundation
import TektonParsers

extension LineExpressionModel {

    /// Evaluate the parsed expression on GPU for `sampleCount` evenly-spaced x
    /// values in [xMin, xMax].  Returns a full LinePlotData on success.
    ///
    /// Unlike sampleLine3DNumeric, this backend handles *non-linear* expressions
    /// (sin, cos, polynomial, etc.).
    func sampleLine3DWithDrJit(
        a: Double,
        b: Double,
        xMin: Double,
        xMax: Double,
        sampleCount: Int
    ) throws -> LinePlotData {
        guard sampleCount >= 3 else {
            throw LineModelError.invalidEquation("sampleCount must be >= 3")
        }

        JITContext.initMetal()

        let n = sampleCount
        let xArr = JITContext.linspace(Float(xMin), Float(xMax), count: n)
        let variables: [String: JITArray] = [
            "x": xArr,
            "a": JITContext.full(Float(a), count: n),
            "b": JITContext.full(Float(b), count: n),
        ]

        let builder = LaTeXMathDrJitBuilder(
            root: root,
            tokenTextByIndex: tokenTextByIndex,
            count: n
        )
        let yArr = try builder.build(variables: variables)
        let yValues = yArr.evaluate()

        guard yValues.count == n else {
            throw LineModelError.parseError(
                "DrJit evaluation returned \(yValues.count) values, expected \(n)"
            )
        }

        var points: [PlotPointN] = []
        points.reserveCapacity(n)
        for i in 0..<n {
            let t  = Double(i) / Double(n - 1)
            let x  = xMin + (xMax - xMin) * t
            points.append(PlotPointN(x: x, y: Double(yValues[i]), z: 0, t: 0, w: 1))
        }

        // Slope/intercept estimated from first two sample points (status bar compat)
        let dx        = (xMax - xMin) / Double(n - 1)
        let slope     = dx > 0 ? (Double(yValues[1]) - Double(yValues[0])) / dx : 0
        let intercept = Double(yValues[0])

        return LinePlotData(
            points: points,
            estimatedSlope: slope,
            estimatedIntercept: intercept,
            backend: "drjit/metal",
            symbolicExpression: nil,
            symbolicDerivative: nil,
            freeSymbols: []
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - LaTeXMathDrJitBuilder
// ─────────────────────────────────────────────────────────────────────────────

private struct LaTeXMathDrJitBuilder {
    let root: LaTeXMathParser.ProgContext
    let tokenTextByIndex: [Int: String]
    let count: Int

    func build(variables: [String: JITArray]) throws -> JITArray {
        guard let expr = root.expr() else {
            throw LineModelError.parseError("Missing expression root")
        }
        return try buildExpr(expr, variables)
    }

    // ── Convenience ──────────────────────────────────────────────────────────

    private func scalar(_ value: Float) -> JITArray {
        JITContext.full(value, count: count)
    }

    // ── Tree walk ─────────────────────────────────────────────────────────────

    private func buildExpr(
        _ ctx: LaTeXMathParser.ExprContext,
        _ vars: [String: JITArray]
    ) throws -> JITArray {
        guard let add = ctx.addExpr() else {
            throw LineModelError.parseError("Missing additive expression")
        }
        return try buildAddExpr(add, vars)
    }

    private func buildAddExpr(
        _ ctx: LaTeXMathParser.AddExprContext,
        _ vars: [String: JITArray]
    ) throws -> JITArray {
        var result: JITArray?
        var pendingOp: String?

        for child in ctx.children ?? [] {
            if let node = child as? LaTeXMathParser.MulExprContext {
                let value = try buildMulExpr(node, vars)
                if let current = result {
                    switch pendingOp {
                    case "+": result = current + value
                    case "-": result = current - value
                    default: throw LineModelError.parseError("Unexpected additive operator")
                    }
                } else {
                    result = value
                }
                pendingOp = nil
            } else if let op = child as? TerminalNode {
                switch op.getSymbol()?.getType() {
                case LaTeXMathParser.Tokens.T__0.rawValue: pendingOp = "+"
                case LaTeXMathParser.Tokens.T__1.rawValue: pendingOp = "-"
                default: break
                }
            }
        }

        guard let result else {
            throw LineModelError.parseError("Empty additive expression")
        }
        return result
    }

    private func buildMulExpr(
        _ ctx: LaTeXMathParser.MulExprContext,
        _ vars: [String: JITArray]
    ) throws -> JITArray {
        var result: JITArray?
        var pendingOp: String?

        for child in ctx.children ?? [] {
            if let node = child as? LaTeXMathParser.UnaryExprContext {
                let value = try buildUnaryExpr(node, vars)
                if let current = result {
                    if let op = pendingOp {
                        switch op {
                        case "*", "\\cdot", "\\times": result = current * value
                        case "/":                       result = current / value
                        default: throw LineModelError.unsupported("mul operator \(op)")
                        }
                    } else if hasLeadingUnarySign(node) {
                        result = current + value
                    } else {
                        result = current * value
                    }
                } else {
                    result = value
                }
                pendingOp = nil
            } else if let op = child as? TerminalNode {
                guard op.getSymbol()?.getType() == LaTeXMathParser.Tokens.MULOP.rawValue else {
                    continue
                }
                guard let symbol = tokenText(of: op) else {
                    throw LineModelError.parseError("Missing multiplicative operator text")
                }
                if ["*", "/", "\\cdot", "\\times"].contains(symbol) {
                    pendingOp = symbol
                }
            }
        }

        guard let result else {
            throw LineModelError.parseError("Empty multiplicative expression")
        }
        return result
    }

    private func buildUnaryExpr(
        _ ctx: LaTeXMathParser.UnaryExprContext,
        _ vars: [String: JITArray]
    ) throws -> JITArray {
        if let powCtx = ctx.powExpr() {
            return try buildPowExpr(powCtx, vars)
        }
        guard let nested = ctx.unaryExpr() else {
            throw LineModelError.parseError("Invalid unary expression")
        }

        let isNeg: Bool
        if let op = ctx.children?.compactMap({ $0 as? TerminalNode }).first,
           op.getSymbol()?.getType() == LaTeXMathParser.Tokens.T__1.rawValue {
            isNeg = true
        } else {
            isNeg = false
        }

        let value = try buildUnaryExpr(nested, vars)
        return isNeg ? -value : value
    }

    private func buildPowExpr(
        _ ctx: LaTeXMathParser.PowExprContext,
        _ vars: [String: JITArray]
    ) throws -> JITArray {
        guard let baseCtx = ctx.postfix() else {
            throw LineModelError.parseError("Missing power base")
        }
        let base = try buildPostfix(baseCtx, vars)

        if let expCtx = ctx.powExpr() {
            let exponent = try buildPowExpr(expCtx, vars)
            // a^b = exp2(log2(a) * b)  — valid for a > 0
            return (base.log2() * exponent).exp2()
        }
        return base
    }

    private func buildPostfix(
        _ ctx: LaTeXMathParser.PostfixContext,
        _ vars: [String: JITArray]
    ) throws -> JITArray {
        guard let prim = ctx.primary() else {
            throw LineModelError.parseError("Missing primary expression")
        }
        var value = try buildPrimary(prim, vars)

        if let scripts = ctx.scripts() {
            var pending: String?
            for child in scripts.children ?? [] {
                if let op = child as? TerminalNode {
                    switch op.getSymbol()?.getType() {
                    case LaTeXMathParser.Tokens.T__2.rawValue: pending = "^"
                    case LaTeXMathParser.Tokens.T__3.rawValue: pending = "_"
                    default: break
                    }
                } else if let grp = child as? LaTeXMathParser.GroupContext {
                    let exponent = try buildGroup(grp, vars)
                    if pending == "^" {
                        value = (value.log2() * exponent).exp2()
                    }
                    pending = nil
                }
            }
        }

        return value
    }

    private func buildGroup(
        _ ctx: LaTeXMathParser.GroupContext,
        _ vars: [String: JITArray]
    ) throws -> JITArray {
        guard let expr = ctx.expr() else {
            throw LineModelError.parseError("Empty group")
        }
        return try buildExpr(expr, vars)
    }

    private func buildPrimary(
        _ ctx: LaTeXMathParser.PrimaryContext,
        _ vars: [String: JITArray]
    ) throws -> JITArray {
        // Numeric literal
        if let numberNode = ctx.NUMBER(), let number = tokenText(of: numberNode) {
            guard let value = Float(number) else {
                throw LineModelError.parseError("Invalid number: \(number)")
            }
            return scalar(value)
        }

        // Identifier (x, a, b, …)
        if let idNode = ctx.ID(), let id = tokenText(of: idNode) {
            if let arr = vars[id] { return arr }
            throw LineModelError.unsupported("unbound identifier \(id)")
        }

        // \pi
        if let greekNode = ctx.greek()?.CMD_GREEK(),
           let greek = tokenText(of: greekNode),
           greek == "\\pi" {
            return scalar(Float.pi)
        }

        // Named functions
        if let funcToken = ctx.CMD_FUNC(),
           let funcName  = tokenText(of: funcToken),
           let arg       = ctx.arg() {
            let v = try buildArg(arg, vars)
            switch funcName {
            case "\\sin":  return v.sin()
            case "\\cos":  return v.cos()
            case "\\tan":
                let s = v.sin(); let c = v.cos(); return s / c
            case "\\exp":
                // exp(x) = exp2(x * log₂e)
                return (v * scalar(Float(M_LOG2E))).exp2()
            case "\\log":
                // ln(x) = log2(x) * ln(2)
                return v.log2() * scalar(Float(M_LN2))
            case "\\sqrt": return v.sqrt()
            default:
                throw LineModelError.unsupported("function \(funcName)")
            }
        }

        // \frac{num}{denom}
        if let frac = ctx.frac() {
            let exprs = frac.expr()
            guard exprs.count == 2 else {
                throw LineModelError.parseError("Invalid fraction")
            }
            let num   = try buildExpr(exprs[0], vars)
            let denom = try buildExpr(exprs[1], vars)
            return num / denom
        }

        // Grouped sub-expression (parentheses / braces)
        if let expr = ctx.expr() {
            return try buildExpr(expr, vars)
        }

        if ctx.nabla() != nil || ctx.partial() != nil {
            throw LineModelError.unsupported("nabla/partial in DrJit evaluator")
        }

        throw LineModelError.unsupported("primary expression form")
    }

    private func buildArg(
        _ ctx: LaTeXMathParser.ArgContext,
        _ vars: [String: JITArray]
    ) throws -> JITArray {
        guard let expr = ctx.expr() else {
            throw LineModelError.parseError("Missing function argument")
        }
        return try buildExpr(expr, vars)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func tokenText(of node: TerminalNode) -> String? {
        guard let symbol = node.getSymbol() else { return nil }
        let idx = symbol.getTokenIndex()
        if idx >= 0, let text = tokenTextByIndex[idx] { return text }
        return symbol.getText()
    }

    private func hasLeadingUnarySign(_ ctx: LaTeXMathParser.UnaryExprContext) -> Bool {
        guard ctx.powExpr() == nil, ctx.unaryExpr() != nil else { return false }
        guard let op = ctx.children?.compactMap({ $0 as? TerminalNode }).first else { return false }
        let type = op.getSymbol()?.getType()
        return type == LaTeXMathParser.Tokens.T__0.rawValue
            || type == LaTeXMathParser.Tokens.T__1.rawValue
    }
}
