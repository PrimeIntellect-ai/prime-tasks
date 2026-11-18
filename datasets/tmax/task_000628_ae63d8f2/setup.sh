#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/lib
    mkdir -p /opt/reference

    # Create failure_state.png
    # Fix ImageMagick security policy to allow writing PNG
    sed -i 's/rights="none" pattern="PNG"/rights="read|write" pattern="PNG"/' /etc/ImageMagick-6/policy.xml || true
    convert -size 600x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -annotate +10+50 "SEQ(SEQ(14) + 3) * (5 - 8)" /app/failure_state.png

    # Create tracing_utils.py
    cat << 'EOF' > /home/user/lib/tracing_utils.py
def trace_diff(state):
    pass
EOF

    # Create buggy evaluator.py
    cat << 'EOF' > /home/user/evaluator.py
import sys
import tracing_utils

def parse_and_eval(expr):
    # Buggy recursive implementation that crashes on unpacking
    nodes = expr.split('SEQ')
    a, b, c = nodes # Unsafe unpack
    return 0

if __name__ == '__main__':
    if len(sys.argv) > 1:
        print(parse_and_eval(sys.argv[1]))
EOF

    # Create .bashrc with typo
    cat << 'EOF' > /home/user/.bashrc
export PYTHONPATH=/home/user/libs
EOF

    # Create oracle binary (executable python script)
    cat << 'EOF' > /opt/reference/evaluator_oracle
#!/usr/bin/env python3
import sys

def SEQ(n):
    n = int(n)
    if n < 0: return 0
    return n * (n + 1) // 2

if __name__ == '__main__':
    if len(sys.argv) > 1:
        expr = sys.argv[1]
        try:
            res = eval(expr, {"__builtins__": {}}, {"SEQ": SEQ})
            print(int(res))
        except Exception:
            print("Error")
EOF
    chmod +x /opt/reference/evaluator_oracle

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
