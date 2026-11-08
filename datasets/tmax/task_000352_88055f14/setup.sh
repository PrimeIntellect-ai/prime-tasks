#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app/bin /app/data/clean /app/data/evil

    cat << 'EOF' > /tmp/legacy_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main() {
    char buf[1024];
    if (!fgets(buf, sizeof(buf), stdin)) return 0;
    int depth = 0;
    for(int i=0; i<strlen(buf); i++) {
        if(buf[i] == '\n' || buf[i] == '\r') continue;
        if(buf[i] == '(') depth++;
        else if(buf[i] == ')') depth--;
        if(depth < 0) abort();
        if(!((buf[i] >= '0' && buf[i] <= '9') || 
             (buf[i] >= 'a' && buf[i] <= 'z') || 
             (buf[i] >= 'A' && buf[i] <= 'Z') ||
             buf[i] == '+' || buf[i] == '-' || buf[i] == '*' || 
             buf[i] == '/' || buf[i] == '^' || buf[i] == '=' || 
             buf[i] == '.' || buf[i] == ' ' || buf[i] == '(' || buf[i] == ')')) {
            abort();
        }
    }
    if(depth != 0) abort();
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_calc.c -o /app/bin/legacy_calc
    strip /app/bin/legacy_calc
    rm /tmp/legacy_calc.c

    python3 -c '
with open("/app/data/clean/sample1.txt", "w", encoding="utf-8") as f:
    f.write("y ＝ ２x ＋ １\n")
    f.write("(a ＋ b)² = a² ＋ ２ab ＋ b²\n")
    f.write("x = \u200B42\n")

with open("/app/data/evil/sample1.txt", "w", encoding="utf-8") as f:
    f.write("y = 2x + 1 (\n")
    f.write("rm -rf /\n")
    f.write("(a + b)) = c\n")
    f.write("x = 42\u037e # The semicolon is a greek question mark homoglyph\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
