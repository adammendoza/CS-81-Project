//
//  ParsingContext.swift
//  Language
//
//  Created by Jaden Geller on 4/8/16.
//  Copyright © 2016 Jaden Geller. All rights reserved.
//

/// Holds any state associated with the parsing process.
public struct ParsingContext {
    public let operatorSpecification: OperatorSpecification<String>
    private let symbols: Set<String>
    public let keywords: Set = ["let"]
    
    public init(operatorSpecification: OperatorSpecification<String>) {
        self.operatorSpecification = operatorSpecification
        self.symbols = Set(operatorSpecification.symbols)
    }
}

extension ParsingContext {
    /// Runs the parser with the specified context.
    public func parse(input: [Token]) throws -> Program {
        return try terminating(program).parse(input)
    }
}

import Parsley

// MARK: Expression
extension ParsingContext {
    
    /// Parses an expression.
    var expression: Parser<Token, Expression> {
        return looselyBoundExpression
    }
    
    /// Parses a loosely bound expression. This is any sort of expression,
    /// even a tightly bound one.
    var looselyBoundExpression: Parser<Token, Expression> {
        // Must check for lambda first since it starts with an identifier (which will
        // be parsed fine by infix expression leaving a dangling right arrow and
        // lambda implementation).
        return hold(coalesce(
            self.lambda.map(Expression.lambda),
            self.infixExpression
        ))
    }
    
    /// Parses a tightly bound expression. This is any type of expression 
    /// that doesn't have ambiguity in this context.
    var tightlyBoundExpression: Parser<Token, Expression> {
        return coalesce(
            // Don't parse `callExpression` here else we'll infinite loop.
            identifier.map(Expression.identifier),
            literal.map(Expression.literal),
            between(parenthesis.left, parenthesis.right, parse: looselyBoundExpression)
        )
    }
        
    /// Parses an infix operator expression tree.
    var infixExpression: Parser<Token, Expression> {
        return operatorExpression(
            parsing: callExpression,
            groupedBy: parenthesis,
            usingSpecification: operatorSpecification,
            matching: { string in
                convert{ Symbol(token: $0) }
                    .require{ $0.text == string }
                    .map(Identifier.symbol)
                    .map(Expression.identifier)
            }
        ).map(Expression.init)
    }
    
    /// Parses a left or right parenthesis.
    var parenthesis: (left: Parser<Token, Token>, right: Parser<Token, Token>) {
        return (left: token(.symbol("(")), right: token(.symbol(")")))
    }
    
    /// Parses an literal.
    var literal: Parser<Token, Literal> {
        return convert{ Literal(token: $0) }
    }
}

// MARK: Identifier
extension ParsingContext {
    /// Parses a identifier, which is a bare word or a symbol surrounded with parenthesis.
    var identifier: Parser<Token, Identifier> {
        return coalesce(
            bare.map(Identifier.bare),
            between(parenthesis.left, parenthesis.right, parse: symbol).map(Identifier.symbol)
        )
    }
    
    /// Parses a bare word.
    var bare: Parser<Token, Bare> {
        return convert{ Bare(token: $0) }
            .require{ !self.keywords.contains($0.text) }
    }
    
    /// Parses a symbol.
    var symbol: Parser<Token, Symbol> {
        return convert{ Symbol(token: $0) }
            .require{ self.symbols.contains($0.text) }
    }
}

// MARK: Lambda
extension ParsingContext {
    
    /// Parses a lambda.
    var lambda: Parser<Token, Lambda> {
        return Parser { state in
            let argumentName = try self.bare.parse(state)
            _ = try token(Token.symbol("->")).parse(state)
            let implementation = try self.looselyBoundExpression.parse(state)
            
            return Lambda(argumentName: .bare(argumentName), implementation: implementation)
        }
    }
}

// MARK: Application
extension ParsingContext {
    
    /// Parses a function call.
    private var callExpression: Parser<Token, Expression> {
        // Cannot left recurse with top-down parser. Thus, we must use a combinator.
        return many1(tightlyBoundExpression).map{ values in
            Expression.call(function: values.first!, arguments: Array(values.dropFirst()))
        }
    }
}

// MARK: Statement
extension ParsingContext {
    
    /// Parses the keyword let.
    func keyword(word: String) -> Parser<Token, ()> {
        return convert{ Bare(token: $0) }.require{ $0.text == word }.discard()
    }
    
    /// Parses a statement.
    var statement: Parser<Token, Statement> {
        return Parser { state in
            _ = try self.keyword("let").parse(state)
            let name = try self.identifier.parse(state)
            _ = try token(.symbol("=")).parse(state)
            let value = try self.expression.parse(state)
            
            return Statement.binding(name, value)
        }
    }
}

// MARK: Program
extension ParsingContext {
    
    /// Parses an entire program.
    var program: Parser<Token, Program> {
        return separated(by: statement, delimiter: token(Token.newLine)).map(Program.init)
    }
}


private let bare: Parser<Token, Bare> = any().map{ if case let .bare(b) = $0 where !["let"].contains(b.text) { return b } else { throw ParseError.UnableToMatch("Bare") } }

extension Expression {
    init(operatorExpression: OperatorExpression<String, Expression>) {
        switch operatorExpression {
        case .infix(let infixOperator, let (lhs, rhs)):
            self = Expression.call(
                function: Expression.identifier(.symbol(Symbol(infixOperator))),
                arguments: [
                    Expression(operatorExpression: lhs),
                    Expression(operatorExpression: rhs)
                ]
            )
//        case .prefix(let prefixOperator, let value):
//            self = Expression.call(
//                function: Expression.identifier(.symbol(Symbol(prefixOperator))),
//                arguments: [Expression(operatorExpression: value)]
//            )
//        case .postfix(let postfixOperator, let value):
//            self = Expression.call(
//                function: Expression.identifier(.symbol(Symbol(postfixOperator))),
//                arguments: [Expression(operatorExpression: value)]
//            )
        case .value(let v):
            self = v
        }
    }
}