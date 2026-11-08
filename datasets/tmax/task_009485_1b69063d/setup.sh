#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang make
    pip3 install pytest

    mkdir -p /home/user/interp
    cd /home/user/interp

    cat << 'EOF' > Makefile
.PHONY: build-linux build-windows

build-linux:
	GOOS=linux GOARCH=amd64 go build -o interp-linux .

build-windows:
	GOOS=windows GOARCH=amd64 go build -o interp-windows.exe .
EOF

    cat << 'EOF' > main.go
package main

import (
	"fmt"
	"io"
	"os"
)

func main() {
	code, err := io.ReadAll(os.Stdin)
	if err != nil {
		panic(err)
	}

	tape := NewRingTape()
	Execute(string(code), tape)
}

func Execute(code string, tape Tape) {
	loopStack := []int{}
	loopMap := map[int]int{}

	for i := 0; i < len(code); i++ {
		if code[i] == '[' {
			loopStack = append(loopStack, i)
		} else if code[i] == ']' {
			start := loopStack[len(loopStack)-1]
			loopStack = loopStack[:len(loopStack)-1]
			loopMap[start] = i
			loopMap[i] = start
		}
	}

	for i := 0; i < len(code); i++ {
		switch code[i] {
		case '>':
			tape.MoveRight()
		case '<':
			tape.MoveLeft()
		case '+':
			tape.Inc()
		case '-':
			tape.Dec()
		case '.':
			fmt.Print(string([]byte{tape.Read()}))
		case ',':
			// Not implemented for this task
		case '[':
			if tape.Read() == 0 {
				i = loopMap[i]
			}
		case ']':
			if tape.Read() != 0 {
				i = loopMap[i]
			}
		}
	}
}
EOF

    cat << 'EOF' > tape.go
package main

type Tape interface {
	MoveLeft()
	MoveRight()
	Inc()
	Dec()
	Read() byte
	Write(val byte)
}

// TODO: Implement RingTape
type RingTape struct {
    // missing fields
}

func NewRingTape() Tape {
	return nil // TODO: return initialized RingTape
}
EOF

    cat << 'EOF' > tape_linux.go
//go:build linux && windows

package main

func OSName() string {
	return "linux"
}
EOF

    cat << 'EOF' > tape_windows.go
//go:build !windows

package main

func OSName() string {
	return "windows"
}
EOF

    cat << 'EOF' > input.df
++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.
EOF

    go mod init interp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
