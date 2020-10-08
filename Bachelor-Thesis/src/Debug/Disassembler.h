#pragma once

#include "Base.h"
#include "Chunk.h"

namespace Lang {

	class Disassembler {
	public:
		static void Disassemble(std::shared_ptr<Chunk> chunk, const char* name);
		static int DisassembleInstruction(std::shared_ptr<Chunk> chunk, int offset);

	private:
		static int ConstantInstruction(const char* name, std::shared_ptr<Chunk> chunk, int offset);
		static int SimpleInstruction(const char* name, int offset);
	};

}
