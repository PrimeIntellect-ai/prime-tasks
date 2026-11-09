#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/math_eval.go
package main

import (
	"C"
	"strconv"
	"strings"
)

//export EvaluateRPN
func EvaluateRPN(expr *C.char) C.double {
	goStr := C.GoString(expr)
	tokens := strings.Split(goStr, " ")
	stack := make([]float64, 0)

	for _, token := range tokens {
		if val, err := strconv.ParseFloat(token, 64); err == nil {
			stack = append(stack, val)
		} else {
			if len(stack) < 2 {
				continue
			}
			b := stack[len(stack)-1]
			a := stack[len(stack)-2]
			stack = stack[:len(stack)-2]
			switch token {
			case "+":
				stack = append(stack, a+b)
			case "-":
				stack = append(stack, a-b)
			case "*":
				stack = append(stack, a*b)
			case "/":
				stack = append(stack, a/b)
			}
		}
	}
	if len(stack) > 0 {
		return C.double(stack[0])
	}
	return C.double(0)
}

func main() {}
EOF

    chmod -R 777 /home/user
