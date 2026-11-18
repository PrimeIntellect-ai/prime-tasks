#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go gcc
pip3 install pytest

mkdir -p /home/user/project/lib /home/user/project/src /home/user/project/bin

cat << 'EOF' > /home/user/project/lib/solver.c
#include "solver.h"
int solve_constraint(int input) {
    return input * input; // Dummy constraint satisfaction logic
}
EOF

cat << 'EOF' > /home/user/project/lib/solver.h
#ifndef SOLVER_H
#define SOLVER_H
int solve_constraint(int input);
#endif
EOF

gcc -shared -o /home/user/project/lib/libsolver.so -fPIC /home/user/project/lib/solver.c

cd /home/user/project/src
go mod init wssolver
go get golang.org/x/net/websocket

cat << 'EOF' > /home/user/project/src/main.go
package main

/*
#cgo CFLAGS: -I../lib
#cgo LDFLAGS: -lsolver
#include "solver.h"
*/
import "C"

import (
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"

	"golang.org/x/net/websocket"
)

var hub = NewHub()

func wsHandler(ws *websocket.Conn) {
	hub.AddClient(ws)
	defer hub.RemoveClient(ws)

	for {
		var msg string
		err := websocket.Message.Receive(ws, &msg)
		if err != nil {
			break
		}

		if strings.HasPrefix(msg, "solve ") {
			parts := strings.Split(msg, " ")
			if len(parts) == 2 {
				val, err := strconv.Atoi(parts[1])
				if err == nil {
					// Call C library
					res := C.solve_constraint(C.int(val))
					hub.Broadcast(fmt.Sprintf("solved: %d", int(res)))
				}
			}
		}
	}
}

func main() {
	http.Handle("/ws", websocket.Handler(wsHandler))
	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

cat << 'EOF' > /home/user/project/src/hub.go
package main

import (
	"golang.org/x/net/websocket"
)

type Hub struct {
	clients map[*websocket.Conn]bool
}

func NewHub() *Hub {
	return &Hub{
		clients: make(map[*websocket.Conn]bool),
	}
}

func (h *Hub) AddClient(ws *websocket.Conn) {
	h.clients[ws] = true
}

func (h *Hub) RemoveClient(ws *websocket.Conn) {
	delete(h.clients, ws)
}

func (h *Hub) Broadcast(msg string) {
	for ws := range h.clients {
		websocket.Message.Send(ws, msg)
	}
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
