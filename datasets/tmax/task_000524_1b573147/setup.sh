#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make gdb binutils
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/src

    # Create the correct source for the binary
    cat << 'EOF' > /tmp/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

void process_line(const char* line) {
    char level[16];
    char msg[512];
    double val;
    if (sscanf(line, "[%15[^]]] %511s %lf", level, msg, &val) == 3) {
        if (strcmp(level, "DEBUG") == 0) {
            char buf[64];
            strcpy(buf, msg);
            printf("{\"level\": \"DEBUG\", \"msg\": \"%s\", \"val\": %f}\n", buf, sqrt(val));
        }
    }
}

int main() {
    char line[1024];
    while (fgets(line, sizeof(line), stdin)) {
        process_line(line);
    }
    return 0;
}
EOF

    # Compile and strip the binary
    gcc -O0 -g -fno-stack-protector /tmp/main.c -lm -o /app/telemetry_parser
    strip /app/telemetry_parser

    # Generate core dump
    cd /app
    ulimit -c unlimited
    sysctl -w kernel.core_pattern=core || true
    echo "[DEBUG] AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA 42.0" | ./telemetry_parser || true

    if ls core* 1> /dev/null 2>&1; then
        mv core* crash.core
    else
        # Fallback if core generation fails in container build
        echo "ELF CORE DUMP FAKE" > crash.core
        echo "[DEBUG] AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA 42.0" >> crash.core
    fi

    # Create the broken source code for the user
    cat << 'EOF' > /home/user/src/main.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

void process_line(const char* line) {
    char level[16];
    char msg[512];
    double val;
    if (sscanf(line, "[%15[^]]] %511s %lf", level, msg, &val) == 3) {
        if (strcmp(level, "DEBUG") == 0) {
            char buf[64];
            strcpy(buf, msg);
            printf("{\"level\": \"DEBUG\", \"msg\": \"%s\", \"val\": %f}\n", buf, sqrt(val));
        }
    }
}

int main() {
    char line[1024];
    while (fgets(line, sizeof(line), stdin)) {
        process_line(line);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/src/Makefile
telemetry_parser_fixed: main.c
	gcc -O2 -Wall -Werror main.c -o /home/user/telemetry_parser_fixed
EOF

    # Create the verification script
    cat << 'EOF' > /verify.py
import subprocess

def run():
    inputs = []
    for i in range(1000):
        if i % 10 == 0:
            inputs.append(f"[DEBUG] {'A'*200} {float(i)}\n")
        else:
            inputs.append(f"[DEBUG] BenignMessage{i} {float(i)}\n")

    with open("/tmp/test_inputs.txt", "w") as f:
        f.writelines(inputs)

    try:
        res = subprocess.run(["/home/user/telemetry_parser_fixed"], input="".join(inputs).encode(), capture_output=True, timeout=5)
        if res.returncode != 0:
            print("success_rate: 0.0")
            return

        out_lines = res.stdout.decode().strip().split('\n')
        if len(out_lines) == 1000:
            print("success_rate: 1.0")
        else:
            print(f"success_rate: {len(out_lines)/1000}")
    except Exception:
        print("success_rate: 0.0")

if __name__ == "__main__":
    run()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
