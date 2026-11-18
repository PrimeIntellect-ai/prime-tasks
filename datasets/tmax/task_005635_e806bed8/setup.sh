#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/repo

cat << 'EOF' > /home/user/repo/assembler.py
class AssemblerVM:
    def __init__(self):
        self.stack = []
        self.memory = {}
        self.pc = 0

    def run(self, code):
        lines = code.split('\n')
        while self.pc < len(lines):
            line = lines[self.pc].strip()
            if not line or line.startswith('#'):
                self.pc += 1
                continue
            parts = line.split()
            op = parts[0]
            if op == 'PUSH':
                self.stack.append(int(parts[1]))
            elif op == 'POP':
                self.stack.pop()
            elif op == 'ADD':
                a = self.stack.pop()
                b = self.stack.pop()
                self.stack.append(a + b)
            elif op == 'SUB':
                a = self.stack.pop()
                b = self.stack.pop()
                self.stack.append(b - a)
            elif op == 'STORE':
                self.memory[parts[1]] = self.stack.pop()
            elif op == 'LOAD':
                self.stack.append(self.memory.get(parts[1], 0))
            elif op == 'JMP':
                self.pc = int(parts[1])
                continue
            elif op == 'JNZ':
                val = self.stack.pop()
                if val != 0:
                    self.pc += int(parts[1]) # BUG: Should be self.pc = int(parts[1])
                    continue
            self.pc += 1
EOF

cat << 'EOF' > /home/user/repo/test_assembler.py
import unittest
from unittest.mock import patch
from assembler import AssemblerVM

class TestAssembler(unittest.TestCase):
    @patch('sys.stdout')
    def test_basic_addition(self): # BUG: Missing mock_stdout parameter
        vm = AssemblerVM()
        vm.run("PUSH 10\nPUSH 20\nADD")
        self.assertEqual(vm.stack[-1], 30)

    def test_jnz(self):
        vm = AssemblerVM()
        code = "PUSH 1\nJNZ 3\nPUSH 50\nPUSH 99"
        vm.run(code)
        self.assertEqual(vm.stack[-1], 99)

if __name__ == '__main__':
    unittest.main()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
