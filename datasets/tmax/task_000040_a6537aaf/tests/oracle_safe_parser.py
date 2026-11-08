import sys
import os

if len(sys.argv) != 2:
    sys.exit(1)

with open(sys.argv[1], 'rb') as f:
    data = f.read()

magic = b"Z3R0_D4Y_P4YL04D\n"
if not data.startswith(magic):
    print("INVALID HEADER")
    sys.exit(1)

payload = data[len(magic):]
decoded = bytes([b ^ 0x42 for b in payload])
sys.stdout.buffer.write(decoded)
