#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak
pip3 install pytest

mkdir -p /app

espeak -w /app/vm_spec.wav "Opcode hex 10 concatenates register B and register C and stores the result in register A. Opcode hex 11 sorts the characters in register B in ascending ASCII order and stores the result in register A. Opcode hex 12 reverses the string in register B and stores it in register A. Opcode hex 13 compares register B and C; if they are identical, it stores the string 'TRUE' in register A, otherwise it stores 'FALSE'."

cat << 'EOF' > /app/oracle_vm
#!/usr/bin/env python3
import sys

def main():
    if len(sys.argv) < 2:
        return
    with open(sys.argv[1], 'rb') as f:
        data = f.read()

    regs = [""] * 16
    pc = 0
    while pc < len(data):
        if pc + 4 > len(data):
            break
        opcode = data[pc]
        ra = data[pc+1]
        rb = data[pc+2]
        rc = data[pc+3]
        pc += 4

        if opcode == 0x01:
            end = pc
            while end < len(data) and data[end] != 0:
                end += 1
            regs[ra] = data[pc:end].decode('utf-8', errors='ignore')
            pc = end + 1
        elif opcode == 0x02:
            print(regs[ra])
        elif opcode == 0x10:
            regs[ra] = regs[rb] + regs[rc]
        elif opcode == 0x11:
            regs[ra] = "".join(sorted(regs[rb]))
        elif opcode == 0x12:
            regs[ra] = regs[rb][::-1]
        elif opcode == 0x13:
            regs[ra] = "TRUE" if regs[rb] == regs[rc] else "FALSE"

if __name__ == "__main__":
    main()
EOF

chmod +x /app/oracle_vm

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
