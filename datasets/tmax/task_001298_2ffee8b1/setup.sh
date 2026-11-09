#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nodejs npm golang-go curl
    pip3 install pytest

    mkdir -p /home/user/app
    cd /home/user/app
    go mod init app
    go get github.com/gorilla/websocket

    cat << 'EOF' > /home/user/server.js
const WebSocket = require('ws');
const wss = new WebSocket.Server({ port: 8080 });

wss.on('connection', function connection(ws) {
  const artifacts = [
    "[ARTIFACT] name:core | deps:;",
    "[ARTIFACT] name:utils | deps:core;",
    "[ARTIFACT] name:app | deps:core,utils;",
    "EOF"
  ];
  artifacts.forEach(a => ws.send(a));
});
EOF

    cat << 'EOF' > /home/user/client.go
package main

import (
	"fmt"
	"log"
	"sync"

	"github.com/gorilla/websocket"
)

func parseArtifact(input string) string {
	state := 0
	name := ""
	for _, c := range input {
		if state == 0 && c == ':' {
			state = 1
		} else if state == 1 && c == ' ' {
			state = 2 
			break // Bug: break instead of continuing or just changing state
		} else if state == 1 {
			// Bug: appending wrong character or skipping
		}
	}
	return name // returns empty
}

func main() {
	url := "ws://localhost:8080"
	c, _, err := websocket.DefaultDialer.Dial(url, nil)
	if err != nil {
		log.Fatal("dial:", err)
	}
	defer c.Close()

	var wg sync.WaitGroup
	ch := make(chan string) 

	for {
		_, message, err := c.ReadMessage()
		if err != nil {
			break
		}
		msg := string(message)
		if msg == "EOF" {
			break
		}

		wg.Add(1)
		go func(m string) {
			defer wg.Done()
			name := parseArtifact(m)
			ch <- name // Deadlock: writing to unbuffered channel with no concurrent reader
		}(msg)
	}

	wg.Wait()
	close(ch)

	for res := range ch {
		fmt.Println("Processed:", res)
	}
}
EOF

    cd /home/user
    npm install ws

    # Ensure gorilla/websocket is available for client.go
    go mod init client
    go get github.com/gorilla/websocket

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
