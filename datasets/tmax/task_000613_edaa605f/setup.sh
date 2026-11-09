#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    # Create /app directory
    mkdir -p /app

    # Create the Python script that implements the logic
    cat << 'EOF' > /app/.hidden_eval.py
#!/usr/bin/env python3
import sys

def main():
    if len(sys.argv) != 3:
        print("INVALID")
        sys.exit(1)

    constraint = sys.argv[1]
    target = sys.argv[2]

    # Dummy implementation for initial state
    if not constraint or not target:
        print("INVALID")
        sys.exit(1)

    print("MATCH")
    sys.exit(0)

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/.hidden_eval.py

    # Create a C wrapper to act as the stripped ELF binary
    cat << 'EOF' > /app/wrapper.c
#include <unistd.h>
int main(int argc, char *argv[]) {
    if (argc != 3) {
        char *newargv1[] = { "/usr/bin/python3", "/app/.hidden_eval.py", NULL };
        execv("/usr/bin/python3", newargv1);
        return 1;
    }
    char *newargv[] = { "/usr/bin/python3", "/app/.hidden_eval.py", argv[1], argv[2], NULL };
    execv("/usr/bin/python3", newargv);
    return 1;
}
EOF

    # Compile and strip the binary
    gcc -O2 /app/wrapper.c -o /app/version_evaluator
    strip /app/version_evaluator
    chmod +x /app/version_evaluator
    rm /app/wrapper.c

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
