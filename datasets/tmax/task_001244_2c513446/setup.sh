#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        wget \
        curl \
        git \
        build-essential \
        cargo \
        rustc

    pip3 install pytest

    # Install Go 1.21
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    rm go1.21.6.linux-amd64.tar.gz
    ln -s /usr/local/go/bin/go /usr/local/bin/go
    ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt

    # Create directories
    mkdir -p /home/user/rust_target/src
    mkdir -p /home/user/go_orchestrator

    # Create Rust files
    cat << 'EOF' > /home/user/rust_target/Cargo.toml
[package]
name = "rust_target"
version = "0.1.0"
edition = "2021"
EOF

    cat << 'EOF' > /home/user/rust_target/src/helper.rs
pub fn get_message() -> String {
    String::from("Hello from the helper!")
}
EOF

    cat << 'EOF' > /home/user/rust_target/src/main.rs
mod helper;
fn main() {
    let msg = helper::get_message();
    // Deliberate compilation error: missing semicolon and typo
    println!("{}", msg)
    broken_code_here
}
EOF

    # Create Go files
    cat << 'EOF' > /home/user/go_orchestrator/go.mod
module orchestrator

go 1.20

require github.com/gorilla/websocket v1.5.0
EOF

    cat << 'EOF' > /home/user/go_orchestrator/server.go
package main

import (
	"bytes"
	"encoding/json"
	"log"
	"net/http"
	"os/exec"
	"strings"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type Response struct {
	Command string `json:"command"`
	Success bool   `json:"success"`
	Output  string `json:"output"`
}

func handleConnections(w http.ResponseWriter, r *http.Request) {
	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Fatal(err)
	}
	defer ws.Close()

	for {
		_, msgBytes, err := ws.ReadMessage()
		if err != nil {
			break
		}
		msg := string(msgBytes)

		// BUG: splits by pipe instead of space
		parts := strings.Split(msg, "|")

		cmdName := strings.TrimSpace(parts[0])
		if len(parts) < 2 {
			ws.WriteJSON(Response{Command: msg, Success: false, Output: "Invalid command format"})
			continue
		}
		path := strings.TrimSpace(parts[1])

		var cmd *exec.Cmd
		if cmdName == "BUILD" {
			cmd = exec.Command("cargo", "build")
			cmd.Dir = path
		} else if cmdName == "RUN" {
			cmd = exec.Command("cargo", "run")
			cmd.Dir = path
		} else {
			ws.WriteJSON(Response{Command: msg, Success: false, Output: "Unknown command"})
			continue
		}

		var out bytes.Buffer
		cmd.Stdout = &out
		cmd.Stderr = &out
		err = cmd.Run()

		ws.WriteJSON(Response{
			Command: msg,
			Success: err == nil,
			Output:  out.String(),
		})
	}
}

func main() {
	http.HandleFunc("/ws", handleConnections)
	log.Println("Server started on :8080")
	err := http.ListenAndServe(":8080", nil)
	if err != nil {
		log.Fatal("ListenAndServe: ", err)
	}
}
EOF

    cat << 'EOF' > /home/user/go_orchestrator/client.go
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"log"
	"os"

	"github.com/gorilla/websocket"
)

func main() {
	scriptFile := flag.String("script", "", "Path to test script")
	outFile := flag.String("output", "", "Path to output JSON")
	flag.Parse()

	if *scriptFile == "" || *outFile == "" {
		log.Fatal("Must provide -script and -output")
	}

	file, err := os.Open(*scriptFile)
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	c, _, err := websocket.DefaultDialer.Dial("ws://localhost:8080/ws", nil)
	if err != nil {
		log.Fatal("dial:", err)
	}
	defer c.Close()

	var results []map[string]interface{}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}
		err := c.WriteMessage(websocket.TextMessage, []byte(line))
		if err != nil {
			log.Fatal("write:", err)
		}
		_, msg, err := c.ReadMessage()
		if err != nil {
			log.Fatal("read:", err)
		}
		var res map[string]interface{}
		json.Unmarshal(msg, &res)
		results = append(results, res)
	}

	outData, _ := json.MarshalIndent(results, "", "  ")
	os.WriteFile(*outFile, outData, 0644)
}
EOF

    cd /home/user/go_orchestrator
    go mod tidy

    # Create user
    useradd -m -s /bin/bash user || true

    # Permissions
    chmod -R 777 /home/user
