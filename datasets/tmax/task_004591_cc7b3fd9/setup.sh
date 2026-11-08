#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make socat redis-server
    pip3 install pytest

    mkdir -p /app/math_eval

    cat << 'EOF' > /app/math_eval/Makefile
math_eval: main.o eval.o
    gcc -o math_eval main.o eval.o

main.o: main.c
    gcc -c main.c

eval.o: eval.c
    gcc -c eval.c
EOF
    # Convert tabs to spaces to break the Makefile
    sed -i 's/\t/    /g' /app/math_eval/Makefile

    cat << 'EOF' > /app/math_eval/main.c
#include <stdio.h>

void eval_loop();

int main() {
    eval_loop();
    return 0;
}
EOF

    cat << 'EOF' > /app/math_eval/eval.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int stack[10];
int sp = 0;

void push(int val) {
    stack[sp++] = val; // no bounds check
}

int pop() {
    return stack[--sp];
}

void eval_loop() {
    char line[256];
    while(fgets(line, sizeof(line), stdin)) {
        char *cmd = strdup(line); // memory leak
        cmd[strcspn(cmd, "\n")] = 0;

        if (strncmp(cmd, "PUSH ", 5) == 0) {
            push(atoi(cmd + 5));
        } else if (strcmp(cmd, "PRINT") == 0) {
            printf("%d\n", pop());
        } else {
            int op = 0;
            if (strcmp(cmd, "ADD") == 0) op = 1;
            else if (strcmp(cmd, "MUL") == 0) op = 2;

            if (op > 0) {
                int a = pop();
                int b = pop();
                switch(op) {
                    case 1:
                        push(a + b);
                        break;
                    case 2:
                        push(a * b);
                        // missing break
                    default:
                        break;
                }
            }
        }
    }
}
EOF

    # Start redis-server automatically when bash is spawned
    echo "redis-server --daemonize yes >/dev/null 2>&1 || true" >> /etc/bash.bashrc
    echo "redis-server --daemonize yes >/dev/null 2>&1 || true" >> /etc/profile

    useradd -m -s /bin/bash user || true
    echo "redis-server --daemonize yes >/dev/null 2>&1 || true" >> /home/user/.bashrc

    chown -R user:user /app
    chmod -R 777 /home/user
