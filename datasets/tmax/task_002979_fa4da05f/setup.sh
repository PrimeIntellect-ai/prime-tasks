#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make golang
    pip3 install pytest

    # Create directories
    mkdir -p /app/c_worker
    mkdir -p /app/reference
    mkdir -p /app/gateway

    # Create broken Makefile
    cat << 'EOF' > /app/c_worker/Makefile
all:
	gcc -o transformer main_cli.c
EOF

    # Create broken transform.c
    cat << 'EOF' > /app/c_worker/transform.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

void transform(char *data, int len) {
    // Bug: off-by-one error and missing logic for some cases
    for (int i = 0; i <= len; i++) { 
        if ((data[i] >= 'a' && data[i] <= 'z')) {
            data[i] = ((data[i] - 'a' + 13) % 26) + 'a';
        } else if ((data[i] >= 'A' && data[i] <= 'Z')) {
            data[i] = ((data[i] - 'A' + 13) % 26) + 'A';
        }
    }
}
EOF

    # Create main_cli.c
    cat << 'EOF' > /app/c_worker/main_cli.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

void transform(char *data, int len);

int main() {
    uint32_t len = 0;
    if (fread(&len, 1, 4, stdin) != 4) return 1;
    char *buf = malloc(len);
    if (!buf) return 1;
    if (fread(buf, 1, len, stdin) != len) {
        free(buf);
        return 1;
    }
    transform(buf, len);
    fwrite(buf, 1, len, stdout);
    free(buf);
    return 0;
}
EOF

    # Create daemon.c
    cat << 'EOF' > /app/c_worker/daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>

void transform(char *data, int len);

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) return 1;
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) return 1;

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(9000);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) return 1;
    if (listen(server_fd, 3) < 0) return 1;

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) continue;
        uint32_t len = 0;
        if (recv(new_socket, &len, 4, MSG_WAITALL) == 4) {
            char *buf = malloc(len);
            if (recv(new_socket, buf, len, MSG_WAITALL) == len) {
                transform(buf, len);
                send(new_socket, buf, len, 0);
            }
            free(buf);
        }
        close(new_socket);
    }
    return 0;
}
EOF

    # Create reference oracle
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main() {
    uint32_t len = 0;
    if (fread(&len, 1, 4, stdin) != 4) return 1;
    char *buf = malloc(len);
    if (!buf) return 1;
    if (fread(buf, 1, len, stdin) != len) {
        free(buf);
        return 1;
    }
    for (uint32_t i = 0; i < len; i++) {
        if ((buf[i] >= 'a' && buf[i] <= 'z')) {
            buf[i] = ((buf[i] - 'a' + 13) % 26) + 'a';
        } else if ((buf[i] >= 'A' && buf[i] <= 'Z')) {
            buf[i] = ((buf[i] - 'A' + 13) % 26) + 'A';
        }
    }
    fwrite(buf, 1, len, stdout);
    free(buf);
    return 0;
}
EOF
    gcc -o /app/reference/transformer_oracle /tmp/oracle.c
    rm /tmp/oracle.c

    # Create Go gateway
    cat << 'EOF' > /app/gateway/main.go
package main

import (
	"encoding/binary"
	"encoding/json"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"os"

	"github.com/joho/godotenv"
)

type RequestPayload struct {
	Payload string `json:"payload"`
}

type ResponsePayload struct {
	Result string `json:"result"`
}

func processHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := ioutil.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	var reqPayload RequestPayload
	if err := json.Unmarshal(body, &reqPayload); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	workerAddr := os.Getenv("WORKER_ADDR")
	if workerAddr == "" {
		workerAddr = "127.0.0.1:9000"
	}

	conn, err := net.Dial("tcp", workerAddr)
	if err != nil {
		http.Error(w, "Worker unavailable", http.StatusInternalServerError)
		return
	}
	defer conn.Close()

	payloadBytes := []byte(reqPayload.Payload)
	lenBuf := make([]byte, 4)
	binary.LittleEndian.PutUint32(lenBuf, uint32(len(payloadBytes)))

	conn.Write(lenBuf)
	conn.Write(payloadBytes)

	resBuf := make([]byte, len(payloadBytes))
	_, err = conn.Read(resBuf)
	if err != nil {
		http.Error(w, "Error reading from worker", http.StatusInternalServerError)
		return
	}

	resPayload := ResponsePayload{Result: string(resBuf)}
	resJSON, _ := json.Marshal(resPayload)

	w.Header().Set("Content-Type", "application/json")
	w.Write(resJSON)
}

func main() {
	godotenv.Load(".env")
	port := os.Getenv("GATEWAY_PORT")
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/process", processHandler)
	log.Printf("Gateway listening on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
EOF

    cd /app/gateway
    go mod init gateway
    go get github.com/joho/godotenv
    go build -o gateway_service main.go
    rm main.go go.mod go.sum

    # Create incorrect .env file
    echo "GATEWAY_PORT=8000" > /app/gateway/.env
    echo "WORKER_ADDR=127.0.0.1:9001" >> /app/gateway/.env

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
