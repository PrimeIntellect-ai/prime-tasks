#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc make jq
    pip3 install pytest

    mkdir -p /home/user/project /home/user/data

    cat << 'EOF' > /home/user/project/evaluator.h
#ifndef EVALUATOR_H
#define EVALUATOR_H
double evaluate_power(double base, double exp);
#endif
EOF

    cat << 'EOF' > /home/user/project/evaluator.c
#include <math.h>
#include "evaluator.h"

double evaluate_power(double base, double exp) {
    return pow(base, exp);
}
EOF

    cat << 'EOF' > /home/user/project/Makefile
all:
	gcc -shared -fPIC -Wl,--no-undefined evaluator.c -o libeval.so
	go build -o eval_tool main.go
EOF
    # Ensure tab character in Makefile
    sed -i 's/^    /\t/' /home/user/project/Makefile

    cat << 'EOF' > /home/user/project/main.go
package main

/*
#cgo CFLAGS: -I.
#cgo LDFLAGS: -L. -leval
#include "evaluator.h"
*/
import "C"
import (
	"fmt"
)

func main() {
	// TODO: Implement the pipeline
	// 1. Read /home/user/data/versions.txt
	// 2. Find highest version >= 1.2.0 and < 2.0.0
	// 3. Merge base.txt and diff_<V>.txt
	// 4. Evaluate using C.evaluate_power(C.double(base), C.double(exp))
	// 5. Write JSON to /home/user/report.json
	fmt.Println("Not implemented")
}
EOF

    cat << 'EOF' > /home/user/data/versions.txt
1.0.0
1.1.9
1.5.2
1.9.5-alpha
2.0.1
1.8.4
2.0.0-beta
EOF

    cat << 'EOF' > /home/user/data/base.txt
ALPHA=2.0,3.0
BETA=4.0,0.5
GAMMA=10.0,2.0
EOF

    cat << 'EOF' > /home/user/data/diff_1.9.5-alpha.txt
BETA=9.0,0.5
DELTA=5.0,2.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
