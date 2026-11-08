#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/legacy_logic.py
import struct

class RingStack:
    def __init__(self, capacity):
        self.capacity = capacity
        self.items = []

    def push(self, item):
        self.items.append(item)
        if len(self.items) > self.capacity:
            self.items.pop(0)

    def pop(self):
        return self.items.pop()

    def rotate_right(self, positions):
        # Legacy Python 2 weird rotation using cmp (just for the sake of migration challenge)
        if not self.items: return
        n = len(self.items)
        positions = positions % n
        if positions == 0: return
        self.items = self.items[-positions:] + self.items[:-positions]

    def get_all(self):
        return self.items

def execute(binary_data):
    stack = RingStack(10)
    pc = 0
    while pc < len(binary_data):
        opcode = ord(binary_data[pc])
        operand = struct.unpack('b', binary_data[pc+1])[0]
        pc += 2

        if opcode == 1:
            stack.push(operand)
        elif opcode == 2:
            a = stack.pop()
            b = stack.pop()
            stack.push(b + a)
        elif opcode == 3:
            a = stack.pop()
            b = stack.pop()
            stack.push(b * a)
        elif opcode == 4:
            positions = stack.pop()
            stack.rotate_right(positions)
        elif opcode == 5:
            break

    return stack.get_all()
EOF
    chmod +x /home/user/legacy_logic.py

    cat << 'EOF' > /home/user/verify.py
import asyncio
import websockets
import base64
import json
import sys

async def test_vm():
    try:
        # PUSH 5, PUSH 10, PUSH -2, ADD, MULTIPLY, PUSH 1, ROTATE, HALT
        # 01 05, 01 0A, 01 FE, 02 00, 03 00, 01 01, 04 00, 05 00
        bytecode = b'\x01\x05\x01\x0a\x01\xfe\x02\x00\x03\x00\x01\x01\x04\x00\x05\x00'
        b64_payload = base64.b64encode(bytecode).decode('utf-8')

        async with websockets.connect("ws://localhost:8765") as websocket:
            await websocket.send(b64_payload)
            response = await websocket.recv()
            result = json.loads(response)

            # Expected logic:
            # PUSH 5  -> [5]
            # PUSH 10 -> [5, 10]
            # PUSH -2 -> [5, 10, -2]
            # ADD     -> pop -2, pop 10 -> 10 + -2 = 8 -> push 8 -> [5, 8]
            # MULT    -> pop 8, pop 5 -> 5 * 8 = 40 -> push 40 -> [40]
            # PUSH 1  -> [40, 1]
            # ROTATE  -> pop 1. rotate [40] by 1 -> [40]
            # HALT

            if result == [40]:
                print("SUCCESS")
                sys.exit(0)
            else:
                print(f"FAILED: Expected [40], got {result}")
                sys.exit(1)
    except Exception as e:
        print(f"ERROR: {e}")
        sys.exit(1)

asyncio.get_event_loop().run_until_complete(test_vm())
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
