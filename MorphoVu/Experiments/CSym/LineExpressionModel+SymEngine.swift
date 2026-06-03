#if os(macOS)
@preconcurrency import Antlr4
import CPPSymEngine
import Foundation
import TektonParsers

extension LineExpressionModel {
    func sampleLine3DWithSymEngine(
        a: Double,
        b: Double,
        xMin: Double,
        xMax: Double,
        sampleCount: Int
    ) throws -> LinePlotData {
        guard sampleCount >= 3 else {
            throw LineModelError.invalidEquation("sampleCount must be >= 3")
        }

        let builder = LaTeXMathSymEngineBuilder(root: root, tokenTextByIndex: tokenTextByIndex)
        let expression = try builder.build()
        let derivative = try expression.differentiated(by: "x").expanded()
        let freeSymbols = try expression.freeSymbolNames()

        let y0 = try evaluate(expression, variables: ["x": 0, "a": a, "b": b])
        let y1 = try evaluate(expression, variables: ["x": 1, "a": a, "b": b])
        let y2 = try evaluate(expression, variables: ["x": 2, "a": a, "b": b])

        let slope = y1 - y0
        let intercept = y0
        let linearResidual = abs((y2 - y1) - slope)
        if linearResidual > 1e-6 {
            throw LineModelError.nonLinear(linearResidual)
        }

        var points: [PlotPointN] = []
        points.reserveCapacity(sampleCount)

        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleCount - 1)
            let x = xMin + (xMax - xMin) * t
            let y = try evaluate(expression, variables: ["x": x, "a": a, "b": b])
            points.append(PlotPointN(x: x, y: y, z: 0, t: 0, w: 1))
        }

        return LinePlotData(
            points: points,
            estimatedSlope: slope,
            estimatedIntercept: intercept,
            backend: "symengine",
            symbolicExpression: expression.description,
            symbolicDerivative: derivative.description,
            freeSymbols: freeSymbols
        )
    }

    private func evaluate(_ expression: Basic, variables: [String: Double]) throws -> Double {
        try expression.substituting(variables).asDouble()
    }
}

private struct LaTeXMathSymEngineBuilder {
    let root: LaTeXMathParser.ProgContext
    let tokenTextByIndex: [Int: String]

    func build() throws -> Basic {
        guard let expr = root.expr() else {
            throw LineModelError.parseError("Missing expression root")
        }
        return try buildExpr(expr)
    }

    private func buildExpr(_ ctx: LaTeXMathParser.ExprContext) throws -> Basic {
        guard let add = ctx.addExpr() else {
            throw LineModelError.parseError("Missing additive expression")
        }
        return try buildAddExpr(add)
    }

    private func buildAddExpr(_ ctx: LaTeXMathParser.AddExprContext) throws -> Basic {
        var result: Basic?
        var pendingOp: String?

        for child in ctx.children ?? [] {
            if let node = child as? LaTeXMathParser.MulExprContext {
                let value = try buildMulExpr(node)
                if let current = result {
                    switch pendingOp {
                    case "+":
                        result = try current + value
                    case "-":
                        result = try current - value
                    default:
                        throw LineModelError.parseError("Unexpected additive operator")
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

    private func buildMulExpr(_ ctx: LaTeXMathParser.MulExprContext) throws -> Basic {
        var result: Basic?
        var pendingOp: String?

        for child in ctx.children ?? [] {
            if let node = child as? LaTeXMathParser.UnaryExprContext {
                let value = try buildUnaryExpr(node)
                if let current = result {
                    if let op = pendingOp {
                        switch op {
                        case "*", "\\cdot", "\\times":
                            result = try current * value
                        case "/":
                            result = try current / value
                        default:
                            throw LineModelError.unsupported("mul operator \(op)")
                        }
                    } else if hasLeadingUnarySign(node) {
                        result = try current + value
                    } else {
                        result = try current * value
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

    private func buildUnaryExpr(_ ctx: LaTeXMathParser.UnaryExprContext) throws -> Basic {
        if let powCtx = ctx.powExpr() {
            return try buildPowExpr(powCtx)
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

        let value = try buildUnaryExpr(nested)
        return sign == "-" ? try value.negated() : value
    }

    private func buildPowExpr(_ ctx: LaTeXMathParser.PowExprContext) throws -> Basic {
        guard let baseCtx = ctx.postfix() else {
            throw LineModelError.parseError("Missing power base")
        }
        let base = try buildPostfix(baseCtx)

        if let expCtx = ctx.powExpr() {
            let exponent = try buildPowExpr(expCtx)
            return try base.pow(exponent)
        }
        return base
    }

    private func buildPostfix(_ ctx: LaTeXMathParser.PostfixContext) throws -> Basic {
        guard let prim = ctx.primary() else {
            throw LineModelError.parseError("Missing primary expression")
        }
        var value = try buildPrimary(prim)

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
                    let groupValue = try buildGroup(grp)
                    if pending == "^" {
                        value = try value.pow(groupValue)
                    }
                    pending = nil
                }
            }
        }

        return value
    }

    private func buildGroup(_ ctx: LaTeXMathParser.GroupContext) throws -> Basic {
        guard let expr = ctx.expr() else {
            throw LineModelError.parseError("Empty group")
        }
        return try buildExpr(expr)
    }

    private func buildPrimary(_ ctx: LaTeXMathParser.PrimaryContext) throws -> Basic {
        if let numberNode = ctx.NUMBER(), let number = tokenText(of: numberNode) {
            if !number.contains("."), !number.contains("e"), !number.contains("E"), let intValue = Int(number) {
                return try Basic.integer(intValue)
            }
            guard let value = Double(number) else {
                throw LineModelError.parseError("Invalid number: \(number)")
            }
            return try Basic.realDouble(value)
        }

        if let idNode = ctx.ID(), let id = tokenText(of: idNode) {
            return try Basic.symbol(id)
        }

        if let greekNode = ctx.greek()?.CMD_GREEK(), let greek = tokenText(of: greekNode), greek == "\\pi" {
            return try Basic.pi()
        }

        if let funcToken = ctx.CMD_FUNC(), let funcName = tokenText(of: funcToken), let arg = ctx.arg() {
            let value = try buildArg(arg)
            switch funcName {
            case "\\sin":
                return try Basic.sin(value)
            case "\\cos":
                return try Basic.cos(value)
            case "\\tan":
                return try Basic.tan(value)
            case "\\exp":
                return try Basic.exp(value)
            case "\\log":
                return try Basic.log(value)
            default:
                throw LineModelError.unsupported("function \(funcName)")
            }
        }

        if let frac = ctx.frac() {
            let exprs = frac.expr()
            guard exprs.count == 2 else {
                throw LineModelError.parseError("Invalid fraction")
            }
            let numerator = try buildExpr(exprs[0])
            let denominator = try buildExpr(exprs[1])
            return try numerator / denominator
        }

        if let expr = ctx.expr() {
            return try buildExpr(expr)
        }

        if ctx.nabla() != nil || ctx.partial() != nil {
            throw LineModelError.unsupported("nabla/partial in symbolic line evaluator")
        }

        throw LineModelError.unsupported("primary expression form")
    }

    private func buildArg(_ ctx: LaTeXMathParser.ArgContext) throws -> Basic {
        guard let expr = ctx.expr() else {
            throw LineModelError.parseError("Missing function argument")
        }
        return try buildExpr(expr)
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
#endif
