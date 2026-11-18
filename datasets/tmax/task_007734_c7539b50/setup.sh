#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gcc jq
    pip3 install pytest

    mkdir -p /home/user/math_dag
    cd /home/user/math_dag

    cat << 'EOF' > math_core.h
#ifndef MATH_CORE_H
#define MATH_CORE_H
double op_add(double a, double b);
double op_mul(double a, double b);
#endif
EOF

    cat << 'EOF' > math_add.c
#include "math_core.h"
double op_add(double a, double b) {
    return a + b;
}
EOF

    cat << 'EOF' > math_mul.c
#include "math_core.h"
double op_mul(double a, double b) {
    return a * b;
}
EOF

    cat << 'EOF' > build.sh
#!/bin/bash
# Broken build script
gcc -c math_add.c
gcc -c math_mul.c
gcc -shared -o libmathcore.so math_add.o
# missing math_mul.o and missing -fPIC
EOF
    chmod +x build.sh

    cat << 'EOF' > graph.json
[
  {"id": "A", "type": "value", "val": 10.0},
  {"id": "B", "type": "value", "val": 5.0},
  {"id": "C", "type": "add", "deps": ["A", "B"]},
  {"id": "D", "type": "mul", "deps": ["C", "A"]},
  {"id": "E", "type": "mul", "deps": ["C", "B"]},
  {"id": "F", "type": "add", "deps": ["D", "E"]}
]
EOF

    cat << 'EOF' > main.go
package main

/*
#cgo CFLAGS: -I.
// Broken cgo directive:
#cgo LDFLAGS: -L. -lmathmissing 
#include "math_core.h"
*/
import "C"
import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
)

// Define your Node struct and evaluation logic here

func main() {
    // Read graph.json
    // Evaluate concurrently
    // Write results.json
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
