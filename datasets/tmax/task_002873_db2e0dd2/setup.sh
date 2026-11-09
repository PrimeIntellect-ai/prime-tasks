#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest hypothesis

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sec-eval/parser
    mkdir -p /home/user/sec-eval/eval

    cat << 'EOF' > /home/user/sec-eval/go.mod
module sec-eval

go 1.20
EOF

    cat << 'EOF' > /home/user/sec-eval/parser/parser.go
package parser

import (
	"sec-eval/eval"
	"strings"
)

type ASTNode struct {
	Value string
}

func Parse(input string) *ASTNode {
	if strings.Contains(input, "PANIC") {
		panic("simulated crash")
	}
	// Circular dependency call for complex nested rules
	if strings.HasPrefix(input, "EVAL:") {
		eval.Evaluate(&ASTNode{Value: input[5:]})
	}
	if input == "" {
		return nil
	}
	return &ASTNode{Value: input}
}
EOF

    cat << 'EOF' > /home/user/sec-eval/eval/eval.go
package eval

import (
	"sec-eval/parser"
)

func Evaluate(node *parser.ASTNode) bool {
	if node == nil {
		return false
	}
	// Circular dependency call for re-parsing
	if node.Value == "REPARSE" {
		parser.Parse("nested")
	}
	return node.Value == "ALLOW"
}
EOF

    cat << 'EOF' > /home/user/sec-eval/main.go
package main

import (
	"fmt"
	"os"
	"sec-eval/eval"
	"sec-eval/parser"
)

func main() {
	defer func() {
		if r := recover(); r != nil {
			os.Exit(2)
		}
	}()

	if len(os.Args) < 2 {
		os.Exit(1)
	}

	node := parser.Parse(os.Args[1])
	if node == nil {
		os.Exit(1)
	}

	result := eval.Evaluate(node)
	if result {
		fmt.Println("ALLOW")
		os.Exit(0)
	} else {
		fmt.Println("DENY")
		os.Exit(0)
	}
}
EOF

    chmod -R 777 /home/user
