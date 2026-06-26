@preconcurrency import Antlr4
import Foundation
import TektonParsers

struct PlotPointN {
    var x: Double
    var y: Double
    var z: Double
    var t: Double
    var w: Double
}

struct LinePlotData {
    let points: [PlotPointN]
    let estimatedSlope: Double
    let estimatedIntercept: Double
    let backend: String
    let symbolicExpression: String?
    let symbolicDerivative: String?
    let freeSymbols: [String]
}

enum LineModelError: Error, CustomStringConvertible {
    case invalidEquation(String)
    case parseError(String)
    case unsupported(String)
    case nonLinear(Double)

    var description: String {
        switch self {
        case .invalidEquation(let text):
            return "Invalid equation: \(text)"
        case .parseError(let text):
            return "Parse error: \(text)"
        case .unsupported(let text):
            return "Unsupported feature: \(text)"
        case .nonLinear(let delta):
            return "Expression is not linear enough (delta=\(delta))."
        }
    }
}

final class ParserErrorCollector: BaseErrorListener {
    nonisolated(unsafe) private(set) var errors: [String] = []

    nonisolated override init() {
        super.init()
    }

    nonisolated override func syntaxError<T>(
        _ recognizer: Recognizer<T>,
        _ offendingSymbol: AnyObject?,
        _ line: Int,
        _ charPositionInLine: Int,
        _ msg: String,
        _ e: AnyObject?
    ) {
        errors.append("line \(line):\(charPositionInLine) \(msg)")
    }
}

struct LineExpressionModel {
    let root: LaTeXMathParser.ProgContext
    let tokenTextByIndex: [Int: String]

    static func parse(_ equation: String) throws -> LineExpressionModel {
        let rhs = try normalizedRHS(from: equation)
        let input = ANTLRInputStream(rhs)
        let lexer = LaTeXMathLexer(input)
        let lexerErrors = ParserErrorCollector()
        lexer.removeErrorListeners()
        lexer.addErrorListener(lexerErrors)

        let tokenStream = CommonTokenStream(lexer)
        try tokenStream.fill()
        var tokenTextByIndex: [Int: String] = [:]
        for token in tokenStream.getTokens() {
            let index = token.getTokenIndex()
            if index >= 0, let text = token.getText() {
                tokenTextByIndex[index] = text
            }
        }
        let parser = try LaTeXMathParser(tokenStream)
        let parserErrors = ParserErrorCollector()
        parser.removeErrorListeners()
        parser.addErrorListener(parserErrors)

        let root = try parser.prog()
        let allErrors = lexerErrors.errors + parserErrors.errors
        if !allErrors.isEmpty {
            throw LineModelError.parseError(allErrors.joined(separator: " | "))
        }

        return LineExpressionModel(root: root, tokenTextByIndex: tokenTextByIndex)
    }

    func sampleLine3D(
        a: Double,
        b: Double,
        xMin: Double,
        xMax: Double,
        sampleCount: Int
    ) throws -> LinePlotData {
        // DrJit: vectorised GPU eval, handles non-linear expressions (sin, cos, poly, …)
        if let drjitPlot = try? sampleLine3DWithDrJit(
            a: a, b: b, xMin: xMin, xMax: xMax, sampleCount: sampleCount
        ) {
            return drjitPlot
        }
        // SymEngine: symbolic fallback — gives derivative info; linear-only
        #if os(macOS) || os(visionOS)
        if let symbolicPlot = try? sampleLine3DWithSymEngine(
            a: a, b: b, xMin: xMin, xMax: xMax, sampleCount: sampleCount
        ) {
            return symbolicPlot
        }
        #endif
        // Numeric: CPU fallback; handles nonlinear expressions without GPU acceleration.
        return try sampleLine3DNumeric(a: a, b: b, xMin: xMin, xMax: xMax, sampleCount: sampleCount)
    }

    private func sampleLine3DNumeric(
        a: Double,
        b: Double,
        xMin: Double,
        xMax: Double,
        sampleCount: Int
    ) throws -> LinePlotData {
        guard sampleCount >= 3 else {
            throw LineModelError.invalidEquation("sampleCount must be >= 3")
        }

        let evaluator = LaTeXMathNumericEvaluator(root: root, tokenTextByIndex: tokenTextByIndex)

        var points: [PlotPointN] = []
        points.reserveCapacity(sampleCount)

        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleCount - 1)
            let x = xMin + (xMax - xMin) * t
            let y = try evaluator.evaluate(variables: ["x": x, "a": a, "b": b])
            points.append(PlotPointN(x: x, y: y, z: 0, t: 0, w: 1))
        }

        let dx = (xMax - xMin) / Double(sampleCount - 1)
        let slope = dx != 0 ? (points[1].y - points[0].y) / dx : 0
        let intercept = points[0].y - slope * points[0].x

        return LinePlotData(
            points: points,
            estimatedSlope: slope,
            estimatedIntercept: intercept,
            backend: "numeric",
            symbolicExpression: nil,
            symbolicDerivative: nil,
            freeSymbols: []
        )
    }

    private static func normalizedRHS(from equation: String) throws -> String {
        let trimmed = equation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LineModelError.invalidEquation("Expression is empty")
        }

        if let equal = trimmed.firstIndex(of: "=") {
            let lhs = trimmed[..<equal].trimmingCharacters(in: .whitespaces)
            let rhs = trimmed[trimmed.index(after: equal)...].trimmingCharacters(in: .whitespaces)
            guard !rhs.isEmpty else {
                throw LineModelError.invalidEquation("Right-hand side is empty")
            }
            if !lhs.isEmpty && lhs != "y" {
                throw LineModelError.invalidEquation("Expected left side to be y")
            }
            return String(rhs)
        }

        return trimmed
    }
}

struct LaTeXMathNumericEvaluator {
    private let root: LaTeXMathParser.ProgContext
    private let tokenTextByIndex: [Int: String]

    init(root: LaTeXMathParser.ProgContext, tokenTextByIndex: [Int: String]) {
        self.root = root
        self.tokenTextByIndex = tokenTextByIndex
    }

    func evaluate(variables: [String: Double]) throws -> Double {
        guard let expr = root.expr() else {
            throw LineModelError.parseError("Missing expression root")
        }
        return try evalExpr(expr, variables)
    }

    private func evalExpr(_ ctx: LaTeXMathParser.ExprContext, _ vars: [String: Double]) throws -> Double {
        guard let add = ctx.addExpr() else {
            throw LineModelError.parseError("Missing additive expression")
        }
        return try evalAddExpr(add, vars)
    }

    private func evalAddExpr(_ ctx: LaTeXMathParser.AddExprContext, _ vars: [String: Double]) throws -> Double {
        var result: Double?
        var pendingOp: String?

        for child in ctx.children ?? [] {
            if let node = child as? LaTeXMathParser.MulExprContext {
                let value = try evalMulExpr(node, vars)
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
                case LaTeXMathParser.Tokens.T__0.rawValue:
                    pendingOp = "+"
                case LaTeXMathParser.Tokens.T__1.rawValue:
                    pendingOp = "-"
                default:
                    break
                }
            }
        }

        guard let result else {
            throw LineModelError.parseError("Empty additive expression")
        }
        return result
    }

    private func evalMulExpr(_ ctx: LaTeXMathParser.MulExprContext, _ vars: [String: Double]) throws -> Double {
        var result: Double?
        var pendingOp: String?

        for child in ctx.children ?? [] {
            if let node = child as? LaTeXMathParser.UnaryExprContext {
                let value = try evalUnaryExpr(node, vars)
                if let current = result {
                    if let op = pendingOp {
                        switch op {
                        case "*", "\\cdot", "\\times":
                            result = current * value
                        case "/":
                            result = current / value
                        default:
                            throw LineModelError.unsupported("mul operator \(op)")
                        }
                    } else if hasLeadingUnarySign(node) {
                        // Grammar can fold + / - into mulExpr as unary terms.
                        // Treat these terms as additive boundaries.
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
                if symbol == "*" || symbol == "/" || symbol == "\\cdot" || symbol == "\\times" {
                    pendingOp = symbol
                }
            }
        }

        guard let result else {
            throw LineModelError.parseError("Empty multiplicative expression")
        }
        return result
    }

    private func evalUnaryExpr(_ ctx: LaTeXMathParser.UnaryExprContext, _ vars: [String: Double]) throws -> Double {
        if let powCtx = ctx.powExpr() {
            return try evalPowExpr(powCtx, vars)
        }
        guard let nested = ctx.unaryExpr() else {
            throw LineModelError.parseError("Invalid unary expression")
        }

        let sign: String
        if let op = ctx.children?.compactMap({ $0 as? TerminalNode }).first {
            switch op.getSymbol()?.getType() {
            case LaTeXMathParser.Tokens.T__1.rawValue:
                sign = "-"
            default:
                sign = "+"
            }
        } else {
            sign = "+"
        }
        let value = try evalUnaryExpr(nested, vars)
        return sign == "-" ? -value : value
    }

    private func evalPowExpr(_ ctx: LaTeXMathParser.PowExprContext, _ vars: [String: Double]) throws -> Double {
        guard let baseCtx = ctx.postfix() else {
            throw LineModelError.parseError("Missing power base")
        }
        let base = try evalPostfix(baseCtx, vars)

        if let expCtx = ctx.powExpr() {
            let exponent = try evalPowExpr(expCtx, vars)
            return Foundation.pow(base, exponent)
        }
        return base
    }

    private func evalPostfix(_ ctx: LaTeXMathParser.PostfixContext, _ vars: [String: Double]) throws -> Double {
        guard let prim = ctx.primary() else {
            throw LineModelError.parseError("Missing primary expression")
        }
        var value = try evalPrimary(prim, vars)

        if let scripts = ctx.scripts() {
            var pending: String?
            for child in scripts.children ?? [] {
                if let op = child as? TerminalNode {
                    switch op.getSymbol()?.getType() {
                    case LaTeXMathParser.Tokens.T__2.rawValue:
                        pending = "^"
                    case LaTeXMathParser.Tokens.T__3.rawValue:
                        pending = "_"
                    default:
                        break
                    }
                } else if let grp = child as? LaTeXMathParser.GroupContext {
                    let groupValue = try evalGroup(grp, vars)
                    if pending == "^" {
                        value = Foundation.pow(value, groupValue)
                    }
                    pending = nil
                }
            }
        }

        return value
    }

    private func evalGroup(_ ctx: LaTeXMathParser.GroupContext, _ vars: [String: Double]) throws -> Double {
        guard let expr = ctx.expr() else {
            throw LineModelError.parseError("Empty group")
        }
        return try evalExpr(expr, vars)
    }

    private func evalPrimary(_ ctx: LaTeXMathParser.PrimaryContext, _ vars: [String: Double]) throws -> Double {
        if let numberNode = ctx.NUMBER(), let number = tokenText(of: numberNode) {
            guard let value = Double(number) else {
                throw LineModelError.parseError("Invalid number: \(number)")
            }
            return value
        }

        if let idNode = ctx.ID(), let id = tokenText(of: idNode) {
            if let value = vars[id] {
                return value
            }
            throw LineModelError.unsupported("unbound identifier \(id)")
        }

        if let greekNode = ctx.greek()?.CMD_GREEK(), let greek = tokenText(of: greekNode), greek == "\\pi" {
            return .pi
        }

        if let funcToken = ctx.CMD_FUNC(), let funcName = tokenText(of: funcToken), let arg = ctx.arg() {
            let value = try evalArg(arg, vars)
            switch funcName {
            case "\\sin": return Foundation.sin(value)
            case "\\cos": return Foundation.cos(value)
            case "\\tan": return Foundation.tan(value)
            case "\\exp": return Foundation.exp(value)
            case "\\log": return Foundation.log(value)
            default: throw LineModelError.unsupported("function \(funcName)")
            }
        }

        if let frac = ctx.frac() {
            let exprs = frac.expr()
            guard exprs.count == 2 else {
                throw LineModelError.parseError("Invalid fraction")
            }
            let numerator = try evalExpr(exprs[0], vars)
            let denominator = try evalExpr(exprs[1], vars)
            return numerator / denominator
        }

        if let expr = ctx.expr() {
            return try evalExpr(expr, vars)
        }

        if ctx.nabla() != nil || ctx.partial() != nil {
            throw LineModelError.unsupported("nabla/partial in numeric line evaluator")
        }

        throw LineModelError.unsupported("primary expression form")
    }

    private func evalArg(_ ctx: LaTeXMathParser.ArgContext, _ vars: [String: Double]) throws -> Double {
        guard let expr = ctx.expr() else {
            throw LineModelError.parseError("Missing function argument")
        }
        return try evalExpr(expr, vars)
    }

    private func tokenText(of node: TerminalNode) -> String? {
        guard let symbol = node.getSymbol() else {
            return nil
        }
        let index = symbol.getTokenIndex()
        if index >= 0, let text = tokenTextByIndex[index] {
            return text
        }
        return symbol.getText()
    }

    private func hasLeadingUnarySign(_ ctx: LaTeXMathParser.UnaryExprContext) -> Bool {
        guard ctx.powExpr() == nil, ctx.unaryExpr() != nil else {
            return false
        }
        guard let op = ctx.children?.compactMap({ $0 as? TerminalNode }).first else {
            return false
        }
        let type = op.getSymbol()?.getType()
        return type == LaTeXMathParser.Tokens.T__0.rawValue || type == LaTeXMathParser.Tokens.T__1.rawValue
    }
}
