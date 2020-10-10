#include "Compiler.h"

#ifdef DEBUG
#include "Debug/Disassembler.h"
#endif


namespace Lang {

	Scanner Compiler::m_Scanner = nullptr;
	std::shared_ptr<Chunk> Compiler::m_CompilingChunk;
	Parser Compiler::m_Parser;

	ParseRule Compiler::m_Rules[] = {
		{ Grouping,	NULL,	Precedence::None },			// LeftParen
		{ NULL,		NULL,	Precedence::None },			// RightParen
		{ NULL,		NULL,	Precedence::None },			// LeftBrace
		{ NULL,		NULL,	Precedence::None },			// RightBrace
		{ Vector,	NULL,	Precedence::None },			// LeftSquare
		{ NULL,		NULL,	Precedence::None },			// RightSquare
		{ NULL,		NULL,	Precedence::None },			// Dot
		{ NULL,		NULL,	Precedence::None },			// Comma
		{ NULL,		NULL,	Precedence::None },			// Semicolon
		{ NULL,		Binary,	Precedence::Term },			// Plus
		{ Unary,	Binary,	Precedence::Term },			// Minus
		{ NULL,		Binary,	Precedence::Factor },		// Star
		{ NULL,		Binary,	Precedence::Factor },		// Slash
		{ Unary,	NULL,	Precedence::None },			// Bang
		{ NULL,		NULL,	Precedence::None },			// Equal
		{ NULL,		Binary,	Precedence::Equality },		// EqualEqual
		{ NULL,		Binary,	Precedence::Equality },		// BangEqual
		{ NULL,		Binary,	Precedence::Comparison },	// Greater
		{ NULL,		Binary,	Precedence::Comparison },	// GreaterEqual
		{ NULL,		Binary,	Precedence::Comparison },	// Less
		{ NULL,		Binary,	Precedence::Comparison },	// LessEqual
		{ NULL,		NULL,	Precedence::None },			// And
		{ NULL,		NULL,	Precedence::None },			// Or
		{ Number,	NULL,	Precedence::None },			// Number
		{ Variable,	NULL,	Precedence::None },			// Identifier
		{ NULL,		NULL,	Precedence::None },			// Var
		{ NULL,		NULL,	Precedence::None },			// Fun
		{ NULL,		NULL,	Precedence::None },			// If
		{ NULL,		NULL,	Precedence::None },			// Else
		{ NULL,		NULL,	Precedence::None },			// Dim
		{ NULL,		NULL,	Precedence::None },			// Shape
		{ NULL,		NULL,	Precedence::None },			// Sel
		{ NULL,		NULL,	Precedence::None },			// Return
		{ NULL,		NULL,	Precedence::None },			// Error
		{ NULL,		NULL,	Precedence::None },			// Eof
	};

	bool Compiler::Compile(const char* source, std::shared_ptr<Chunk> chunk) {
		m_Scanner = Scanner(source);
		m_CompilingChunk = chunk;
		m_Parser.HadError = false;
		m_Parser.InPanicMode = false;

		Advance();
		while (!Match(TokenType::Eof)) {
			Declaration();
		}

		EndCompiler();
		return !m_Parser.HadError;
	}

	void Compiler::EndCompiler() {
		EmitByte((uint16_t)OpCode::Return);
		#ifdef DEBUG
		if (!m_Parser.HadError) {
			Disassembler::Disassemble(GetCurrentChunk(), "Code");
		}
		#endif
	}

	void Compiler::Advance() {
		m_Parser.Previous = m_Parser.Current;
		while (true) {
			m_Parser.Current = m_Scanner.ScanToken();
			if (m_Parser.Current.Type != TokenType::Error) {
				break;
			}

			Error(&m_Parser.Current, m_Parser.Current.Start);
		}
	}

	bool Compiler::Check(TokenType type) {
		return m_Parser.Current.Type == type;
	}

	bool Compiler::Match(TokenType type) {
		if (!Check(type)) return false;
		Advance();
		return true;
	}

	void Compiler::Consume(TokenType type, const char* msg) {
		if (Check(type)) {
			Advance();
			return;
		}

		Error(&m_Parser.Current, msg);
	}

	void Compiler::ParsePrecedence(Precedence precedence) {
		Advance();

		ParseFn prefixRule = GetRule(m_Parser.Previous.Type)->Prefix;
		if (prefixRule == NULL) {
			Error(&m_Parser.Previous, "Expect expression");
			return;
		}

		bool canAssign = precedence <= Precedence::Assignment;
		prefixRule(canAssign);

		while (precedence <= GetRule(m_Parser.Current.Type)->Precedence) {
			Advance();
			ParseFn infixRule = GetRule(m_Parser.Previous.Type)->Infix;
			infixRule(canAssign);
		}

		if (canAssign && Match(TokenType::Equal)) {
			Error(&m_Parser.Previous, "Invalid assignment target");
		}
	}

	void Compiler::Grouping(bool canAssign) {
		Expression();
		Consume(TokenType::RightParen, "Expect `)' after expression");
	}

	void Compiler::Declaration() {
		if (Match(TokenType::Var)) {
			VarDeclaration();
		} else {
			Statement();
		}

		if (m_Parser.InPanicMode) {
			Synchronize();
		}
	}

	void Compiler::VarDeclaration() {

	}

	void Compiler::Expression() {
		ParsePrecedence(Precedence::Assignment);
	}

	void Compiler::Statement() {
		if (Match(TokenType::Return)) {
			ReturnStatement();
		} else {
			ExpressionStatement();
		}
	}

	void Compiler::ReturnStatement() {
		Expression();
		Consume(TokenType::Semicolon, "Expect `;' after value");
		EmitByte((uint8_t)OpCode::Return);
	}

	void Compiler::ExpressionStatement() {
		Expression();
		Consume(TokenType::Semicolon, "Expect `;' after expression");
		EmitByte((uint8_t)OpCode::Pop);
	}

	void Compiler::Variable(bool canAssign) {
		NamedVariable(m_Parser.Previous, canAssign);
	}

	void Compiler::NamedVariable(Token name, bool canAssign) {
		uint8_t arg = 0;
		if (canAssign && Match(TokenType::Equal)) {
			Expression();
			EmitBytes((uint8_t)OpCode::SetLocal, arg);
		} else {
			EmitByte((uint8_t)OpCode::GetLocal);
		}
	}

	void Compiler::Vector(bool canAssign) {
		std::vector<double> values;
		while (Match(TokenType::Number)) {
			values.push_back(strtod(m_Parser.Previous.Start, NULL));
			if (!Match(TokenType::Comma)) {
				break;
			}
		}

		Consume(TokenType::RightSquare, "Expect `]' after vector");
		EmitConstant({ 1, { (uint16_t)values.size() }, values });
	}

	void Compiler::Number(bool canAssign) {
		double value = strtod(m_Parser.Previous.Start, NULL);
		EmitConstant(value);
	}

	void Compiler::Binary(bool canAssign) {
		TokenType operatorType = m_Parser.Previous.Type;
		ParseRule* rule = GetRule(operatorType);
		ParsePrecedence((Precedence)((int)rule->Precedence + 1));

		switch (operatorType) {
			case TokenType::EqualEqual:		EmitByte((uint16_t)OpCode::Equal); break;
			case TokenType::BangEqual:		EmitByte((uint16_t)OpCode::NotEqual); break;
			case TokenType::Greater:		EmitByte((uint16_t)OpCode::Greater); break;
			case TokenType::GreaterEqual:	EmitByte((uint16_t)OpCode::GreaterEqual); break;
			case TokenType::Less:			EmitByte((uint16_t)OpCode::Less); break;
			case TokenType::LessEqual:		EmitByte((uint16_t)OpCode::LessEqual); break;
			case TokenType::Plus:			EmitByte((uint16_t)OpCode::Add); break;
			case TokenType::Minus:			EmitByte((uint16_t)OpCode::Subtract); break;
			case TokenType::Star:			EmitByte((uint16_t)OpCode::Multiply); break;
			case TokenType::Slash:			EmitByte((uint16_t)OpCode::Divide); break;

			default:
				fprintf(stderr, "Invalid operator `%d'", operatorType);
				return;
		}
	}

	void Compiler::Unary(bool canAssign) {
		TokenType operatorType = m_Parser.Previous.Type;
		Expression();
		ParsePrecedence(Precedence::Unary);

		switch (operatorType) {
			case TokenType::Bang:	EmitByte((uint16_t)OpCode::Not); break;
			case TokenType::Minus:	EmitByte((uint16_t)OpCode::Negate); break;

			default:
				fprintf(stderr, "Invalid operator `%d'", operatorType);
				return;
		}
	}

	void Compiler::EmitByte(uint16_t byte) {
		GetCurrentChunk()->Write(byte, m_Parser.Previous.Line);
	}

	void Compiler::EmitBytes(uint16_t byte1, uint16_t byte2) {
		EmitByte(byte1);
		EmitByte(byte2);
	}

	void Compiler::EmitConstant(Value value) {
		EmitBytes((uint16_t)OpCode::Constant, MakeConstant(value));
	}

	uint16_t Compiler::MakeConstant(Value value) {
		return GetCurrentChunk()->AddConstant(value);
	}

	std::shared_ptr<Chunk> Compiler::GetCurrentChunk() {
		return m_CompilingChunk;
	}

	ParseRule* Compiler::GetRule(TokenType type) {
		return &m_Rules[(uint16_t)type];
	}

	void Compiler::Synchronize() {
		m_Parser.InPanicMode = false;
		while (Check(TokenType::Eof)) {
			if (m_Parser.Previous.Type == TokenType::Semicolon) {
				return;
			}

			switch (m_Parser.Current.Type) {
				case TokenType::Var:
				case TokenType::Fun:
				case TokenType::If:
				case TokenType::Dim:
				case TokenType::Shape:
				case TokenType::Sel:
				case TokenType::Return:
					return;
			}
		}
	}

	void Compiler::Error(Token* token, const char* msg) {
		if (m_Parser.InPanicMode) return;
		m_Parser.HadError = true;
		m_Parser.InPanicMode = true;

		fprintf(stderr, "[line %d] Error", token->Line);
		if (token->Type == TokenType::Eof) {
			fprintf(stderr, " at end: %s\n", msg);
		} else if (token->Type != TokenType::Error) {
			fprintf(stderr, " at `%.*s': %s\n", token->Length, token->Start, msg);
		}
	}

}
