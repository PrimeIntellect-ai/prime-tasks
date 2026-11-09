#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx imagemagick tesseract-ocr tesseract-ocr-eng fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/bin
    mkdir -p /home/user/math_engine/c_src

    # Create grammar image
    echo "EXPR ::= TERM (('+' | '-') TERM)*" > /tmp/grammar.txt
    echo "TERM ::= FACTOR (('*' | '/') FACTOR)*" >> /tmp/grammar.txt
    echo "FACTOR ::= NUMBER | '(' EXPR ')'" >> /tmp/grammar.txt
    echo "NUMBER ::= [0-9]+" >> /tmp/grammar.txt
    convert -background white -fill black -font DejaVu-Sans -pointsize 18 text:/tmp/grammar.txt /app/grammar.png

    # Create dummy python2 files
    echo "print 'parser'" > /home/user/math_engine/parser.py
    echo "print 'server'" > /home/user/math_engine/server.py

    # Create dummy C file
    cat << 'EOF' > /home/user/math_engine/c_src/fast_eval.c
#include <string.h>
#include <stdlib.h>
void eval() {
    char buf[10];
    strcpy(buf, "overflow_this_buffer_intentionally");
}
EOF

    # Create oracle
    cat << 'EOF' > /app/bin/math_oracle_v3
#!/bin/bash
echo "oracle"
EOF
    chmod +x /app/bin/math_oracle_v3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
