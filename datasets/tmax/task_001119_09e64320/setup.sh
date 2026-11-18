#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    golang \
    gcc \
    make \
    tesseract-ocr \
    imagemagick \
    fonts-dejavu-core

pip3 install pytest

mkdir -p /home/user/project/clib
mkdir -p /home/user/project/server
mkdir -p /home/user/project/config
mkdir -p /home/user/project/telemetry
mkdir -p /app

# Create image with text
convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
  -draw "text 10,40 'DEPLOYMENT_CONFIG:' text 10,80 'PORT=8443' text 10,120 'API_TOKEN=AlphaBravo99'" \
  /app/arch.png

# Create go.mod
cat << 'EOF' > /home/user/project/go.mod
module project

go 1.18
EOF

# Create C files
cat << 'EOF' > /home/user/project/clib/core.c
#include "core.h"
int process_data(int a) {
    return a * 2;
}
EOF

cat << 'EOF' > /home/user/project/clib/core.h
#ifndef CORE_H
#define CORE_H
int process_data(int a);
#endif
EOF

# Create broken Makefile (using spaces instead of tabs to cause make error)
cat << 'EOF' > /home/user/project/clib/Makefile
CC=gcc
CFLAGS=-Wall -Wextra

all: libcore.a

libcore.a: core.o
    ar rcs libcore.a core.o

core.o: core.c
    $(CC) $(CFLAGS) -c core.c -o core.o

clean:
    rm -f *.o *.a
EOF

# Create Go files
cat << 'EOF' > /home/user/project/server/server.go
package server

import (
	"encoding/json"
	"net/http"
	"os"
	"project/config"
)

type Server struct {
	Config config.AppConfig
}

func NewServer(cfg config.AppConfig) *Server {
	s := &Server{Config: cfg}
	config.ApplyDefaults(s)
	return s
}

func (s *Server) Start() error {
	http.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
		token := r.Header.Get("Authorization")
		expected := "Bearer " + os.Getenv("API_TOKEN")
		if token != expected || expected == "Bearer " {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
	})
	port := os.Getenv("SERVER_PORT")
	if port == "" {
		port = "8080"
	}
	return http.ListenAndServe(":"+port, nil)
}
EOF

cat << 'EOF' > /home/user/project/config/config.go
package config

import "project/server"

type AppConfig struct {
	MaxConns int
}

func ApplyDefaults(s *server.Server) {
	if s.Config.MaxConns == 0 {
		s.Config.MaxConns = 100
	}
}
EOF

cat << 'EOF' > /home/user/project/telemetry/telemetry.go
//go:build !minimal

package telemetry

import "fmt"

func InitTelemetry() {
	// syntax error to ensure it fails if compiled
	fmt.Println("Telemetry initialized"
}
EOF

cat << 'EOF' > /home/user/project/main.go
package main

import (
	"log"
	"project/config"
	"project/server"
)

// #cgo CFLAGS: -I./clib
// #cgo LDFLAGS: -L./clib -lcore
// #include "core.h"
import "C"

func main() {
	C.process_data(10)
	cfg := config.AppConfig{}
	srv := server.NewServer(cfg)
	log.Fatal(srv.Start())
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
