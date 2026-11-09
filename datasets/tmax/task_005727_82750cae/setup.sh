#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/expr_project/src
    mkdir -p /home/user/expr_project/lib

    cat << 'EOF' > /home/user/expr_project/lib/eval.h
#ifndef EVAL_H
#define EVAL_H

int eval_rpn(const char* expr);

#endif
EOF

    cat << 'EOF' > /home/user/expr_project/lib/eval.c
#include "eval.h"
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>

int eval_rpn(const char* expr) {
    int stack[4];
    int sp = 0;
    const char* p = expr;

    while (*p) {
        if (isspace(*p)) {
            p++;
            continue;
        }
        if (isdigit(*p)) {
            int val = 0;
            while (isdigit(*p)) {
                val = val * 10 + (*p - '0');
                p++;
            }
            // BUG: No bounds check here
            stack[sp++] = val;
        } else {
            if (sp < 2) return -999;
            int b = stack[--sp];
            int a = stack[--sp];
            switch (*p) {
                case '+': stack[sp++] = a + b; break;
                case '-': stack[sp++] = a - b; break;
                case '*': stack[sp++] = a * b; break;
                case '/': stack[sp++] = a / b; break;
                default: return -999;
            }
            p++;
        }
    }
    return sp > 0 ? stack[0] : -999;
}
EOF

    cat << 'EOF' > /home/user/expr_project/src/main.go
package main

// #cgo CFLAGS: -I.
// #include "eval.h"
import "C"
import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("No expression provided")
		return
	}
	expr := C.CString(os.Args[1])
	res := C.eval_rpn(expr)
	fmt.Printf("%d\n", int(res))
}
EOF

    cat << 'EOF' > /home/user/expr_project/build.sh
#!/bin/bash
# Broken build script
export CGO_ENABLED=0
cd src
go build -o ../expr_app main.go
EOF
    chmod +x /home/user/expr_project/build.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
