#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang-go
    pip3 install pytest

    mkdir -p /home/user/polybuild/c_src
    mkdir -p /home/user/polybuild/go_src

    cat << 'EOF' > /home/user/polybuild/c_src/worker.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    int *arr = malloc(5 * sizeof(int));
    // BUG: Off-by-one error causes heap buffer overflow
    for(int i = 0; i <= 5; i++) { 
        arr[i] = i;
    }
    printf("Worker initialized\n");
    free(arr);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/polybuild/go_src/builder.go
package main

import (
	"bufio"
	"os/exec"
	"github.com/gorilla/websocket"
)

// StreamBuild executes a shell command and streams its stdout line-by-line over the WebSocket.
func StreamBuild(ws *websocket.Conn, cmdString string) error {
	// TODO: Implement concurrency, channel-based stdout reading, and WebSocket streaming here.
    return nil
}
EOF

    cat << 'EOF' > /home/user/polybuild/go_src/builder_test.go
package main

import (
	"testing"
)

// TODO: Implement TestStreamBuild using httptest and Gorilla websocket mocks.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
