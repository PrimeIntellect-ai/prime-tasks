#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang ffmpeg curl
    pip3 install pytest

    mkdir -p /app/patch-api/router
    mkdir -p /app/patch-api/handlers
    mkdir -p /app/tests/evil
    mkdir -p /app/tests/clean

    # Create Go module
    cat << 'EOF' > /app/patch-api/go.mod
module patch-api

go 1.18
EOF

    cat << 'EOF' > /app/patch-api/main.go
package main

import (
	"fmt"
	"net/http"
	"patch-api/router"
)

func main() {
	r := router.NewRouter()
	fmt.Println("Server starting on :8080")
	http.ListenAndServe(":8080", r)
}
EOF

    cat << 'EOF' > /app/patch-api/router/router.go
package router

import (
	"net/http"
	"patch-api/handlers"
)

var GlobalRouter *http.ServeMux

func NewRouter() *http.ServeMux {
	GlobalRouter = http.NewServeMux()
	GlobalRouter.HandleFunc("/api/v1/patch", handlers.PatchHandler)
	return GlobalRouter
}
EOF

    cat << 'EOF' > /app/patch-api/handlers/patch.go
package handlers

import (
	"net/http"
	"patch-api/router"
)

func PatchHandler(w http.ResponseWriter, r *http.Request) {
	// Circular dependency
	_ = router.GlobalRouter
	w.WriteHeader(http.StatusOK)
}
EOF

    # Create dummy video
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=45 -c:v libx264 /app/incident.mp4

    # Create test patches
    cat << 'EOF' > /app/tests/evil/evil1.patch
--- a/file.txt
+++ b/../../../etc/shadow
@@ -1,3 +1,4 @@
 line1
 line2
EOF

    cat << 'EOF' > /app/tests/clean/clean1.patch
--- a/src/main.go
+++ b/src/main.go
@@ -1,3 +1,4 @@
 line1
 line2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
