#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang git file
    pip3 install pytest

    mkdir -p /home/user/cimonitor/parser
    mkdir -p /home/user/cimonitor/state
    mkdir -p /home/user/cimonitor/processor
    mkdir -p /home/user/cimonitor/sys

    cd /home/user/cimonitor
    go mod init cimonitor

    cat << 'EOF' > main.go
package main

import (
	"cimonitor/processor"
	"cimonitor/sys"
	"fmt"
)

func main() {
	fmt.Println("Starting cimonitor on arch:", sys.Arch())
	processor.Run()
}
EOF

    cat << 'EOF' > processor/processor.go
package processor

import (
	"cimonitor/parser"
	"fmt"
	"sync"
)

func Run() {
	jobs := make(chan string, 10)
	results := make(chan string, 10)
	var wg sync.WaitGroup

	for i := 0; i < 3; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := range jobs {
				results <- parser.Parse(j)
			}
		}()
	}

	jobs <- "pipeline started"
	jobs <- "tests running"
	jobs <- "deployment failed"
	close(jobs)

	wg.Wait()
	// BUG: results channel is never closed, causing the range loop below to deadlock.

	for r := range results {
		fmt.Println("Processed:", r)
	}
}
EOF

    cat << 'EOF' > parser/parser.go
package parser

import "cimonitor/state"

func Parse(line string) string {
	m := state.NewMachine()
	return m.State() + ": " + line
}

func Helper() string {
	return "helper_val"
}
EOF

    cat << 'EOF' > state/state.go
package state

import "cimonitor/parser"

type Machine struct{}

func NewMachine() *Machine {
	return &Machine{}
}

func (m *Machine) State() string {
	// BUG: circular dependency importing parser.Helper()
	return "state-" + parser.Helper()
}
EOF

    cat << 'EOF' > sys/sys_linux_x86.go
package sys

func Arch() string {
	return "amd64"
}
EOF

    cat << 'EOF' > sys/sys_linux_arm.go
package sys

func Arch() string {
	return "arm64"
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
