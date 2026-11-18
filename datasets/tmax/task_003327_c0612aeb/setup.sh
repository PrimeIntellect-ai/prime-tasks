#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/mobile_pipeline

    cat << 'EOF' > /home/user/mobile_pipeline/mobile_emulator.py
import os
import math

def patch_math():
    if os.environ.get("TARGET_ARCH") == "arm64":
        # Simulate lower precision for ARM emulator
        original_sin = math.sin
        math.sin = lambda x: round(original_sin(x), 2)

patch_math()
EOF

    cat << 'EOF' > /home/user/mobile_pipeline/build_lookup.py
import os
import sys
# Bug: 'from math import sin' happens before mobile_emulator patches it.
from math import sin
import mobile_emulator

def generate_table():
    target = os.environ.get("TARGET_ARCH", "x86")
    with open(f"lookup_{target}.h", "w") as f:
        f.write("float sin_lookup[] = {\n")
        for i in range(10):
            val = sin(i * 0.1)
            f.write(f"    {val}f,\n")
        f.write("};\n")

if __name__ == "__main__":
    generate_table()
EOF

    cat << 'EOF' > /home/user/mobile_pipeline/test_lookup.py
import os
import mobile_emulator # This correctly patches math first
from math import sin

target = os.environ.get("TARGET_ARCH", "x86")
expected = [sin(i * 0.1) for i in range(10)]

try:
    with open(f"lookup_{target}.h", "r") as f:
        lines = f.readlines()[1:-1]
    actual = [float(line.strip().replace("f,", "")) for line in lines]

    if actual == expected:
        print("PASS")
        import sys; sys.exit(0)
    else:
        print("FAIL: Values do not match emulator precision")
        import sys; sys.exit(1)
except Exception as e:
    print(f"FAIL: {e}")
    import sys; sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
