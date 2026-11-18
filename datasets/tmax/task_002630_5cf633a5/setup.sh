#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make gcc redis-server curl wget tar
    pip3 install pytest

    # Install Go 1.21 to satisfy modern go-redis dependencies
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    ln -s /usr/local/go/bin/go /usr/bin/go

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/c_eval
    mkdir -p /home/user/app/gateway
    mkdir -p /home/user/app/corpora/clean
    mkdir -p /home/user/app/corpora/evil

    # C Eval Backend
    cat << 'EOF' > /home/user/app/c_eval/Makefile
all: libmatheval.so eval_server

libmatheval.so: matheval.c
	gcc -shared -fPIC -o libmatheval.so matheval.c

eval_server: server.c
	gcc -o eval_server server.c
EOF

    cat << 'EOF' > /home/user/app/c_eval/matheval.c
#include <stdio.h>
#include <stdlib.h>

int evaluate(const char* expr) {
    return 42;
}
EOF

    cat << 'EOF' > /home/user/app/c_eval/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

extern int evaluate(const char* expr);

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) {
        perror("setsockopt");
        exit(EXIT_FAILURE);
    }
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8081);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }
    if (listen(server_fd, 3) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            exit(EXIT_FAILURE);
        }
        read(new_socket, buffer, 1024);
        int res = evaluate(buffer);
        char response[1024];
        sprintf(response, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n%d", res);
        send(new_socket, response, strlen(response), 0);
        close(new_socket);
    }
    return 0;
}
EOF

    # Go Gateway
    cat << 'EOF' > /home/user/app/gateway/main.go
package main

import (
	"io/ioutil"
	"net/http"

	"github.com/redis/go-redis/v9"
)

var rdb *redis.Client

func init() {
	rdb = redis.NewClient(&redis.Options{
		Addr: "localhost:6379",
	})
}

func evalHandler(w http.ResponseWriter, r *http.Request) {
	body, _ := ioutil.ReadAll(r.Body)
	expr := string(body)

	err := Sanitize(expr)
	if err != nil {
		http.Error(w, "Bad Request", http.StatusBadRequest)
		return
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte("42"))
}

func main() {
	http.HandleFunc("/eval", evalHandler)
	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /home/user/app/gateway/sanitizer.go
package main

func Sanitize(expr string) error {
	return nil
}
EOF

    cd /home/user/app/gateway
    go mod init gateway
    go get github.com/redis/go-redis/v9

    # Corpora
    echo "(5 + 3) * 2" > /home/user/app/corpora/clean/test1.expr
    echo "10 / 2" > /home/user/app/corpora/clean/test2.expr

    echo "1 / 0" > /home/user/app/corpora/evil/divzero.expr
    echo "a + 5" > /home/user/app/corpora/evil/vars.expr
    echo "((5 + 1)" > /home/user/app/corpora/evil/mismatch.expr

    chmod -R 777 /home/user
