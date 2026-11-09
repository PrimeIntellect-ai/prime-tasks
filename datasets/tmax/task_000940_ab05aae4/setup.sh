#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /app/tinyserver-0.1

    cat << 'EOF' > /app/tinyserver-0.1/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

void decode_payload(const char* input, char* output) {
    char decoded_buffer[1024];
    strcpy(decoded_buffer, input); 
    strcpy(output, decoded_buffer); // Vulnerability: Buffer overflow
}

int authenticate(const char* user, const char* pass) {
    if (strcmp(user, "admin") == 0) {
        return 1; // Vulnerability: Logic flaw, bypasses password check
    }
    if (strcmp(user, "user") == 0 && strcmp(pass, "pass") == 0) {
        return 1;
    }
    return 0;
}

void handle_client(int client_sock) {
    char buffer[2048];
    memset(buffer, 0, sizeof(buffer));
    int n = read(client_sock, buffer, sizeof(buffer)-1);
    if (n <= 0) {
        close(client_sock);
        return;
    }

    char user[64], pass[64], payload[1024];
    if (sscanf(buffer, "%63s %63s %1023s", user, pass, payload) == 3) {
        if (authenticate(user, pass)) {
            char decoded[128];
            decode_payload(payload, decoded);
            write(client_sock, "OK\n", 3);
        } else {
            write(client_sock, "DENIED\n", 7);
        }
    } else {
        write(client_sock, "ERROR\n", 6);
    }
    close(client_sock);
}

int main(int argc, char *argv[]) {
    int port = 8080;
    if (argc > 1) port = atoi(argv[1]);

    int server_sock = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    bind(server_sock, (struct sockaddr *)&address, sizeof(address));
    listen(server_sock, 5);

    while (1) {
        int client_sock = accept(server_sock, NULL, NULL);
        if (client_sock >= 0) {
            handle_client(client_sock);
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/tinyserver-0.1/Makefile
CC=gcc
CFLAGS=-Wall -O0 -fno-stack-protector

all: server

server: server.c
	$(CC) $(CFLAGS) server.c -o server

clean:
	rm -f server
EOF

    cat << 'EOF' > /app/evaluate_server.py
import subprocess
import socket
import time
import sys

def test():
    if len(sys.argv) < 2:
        print("Usage: evaluate_server.py <binary>")
        sys.exit(1)

    binary = sys.argv[1]

    p = subprocess.Popen([binary, "8080"])
    time.sleep(0.5)

    correct = 0
    total = 200

    def send_req(user, pwd, payload):
        try:
            s = socket.socket(socket.AF_INET, socket.socket.SOCK_STREAM)
            s.settimeout(1.0)
            s.connect(("127.0.0.1", 8080))
            s.sendall(f"{user} {pwd} {payload}".encode())
            resp = s.recv(1024).decode().strip()
            s.close()
            return resp
        except Exception:
            return "CRASH"

    try:
        for i in range(total):
            if i % 4 == 0:
                resp = send_req("user", "pass", "short_payload")
                if resp == "OK": correct += 1
            elif i % 4 == 1:
                resp = send_req("user", "wrong", "short_payload")
                if resp == "DENIED": correct += 1
            elif i % 4 == 2:
                resp = send_req("admin", "wrong", "short_payload")
                if resp == "DENIED": correct += 1
            elif i % 4 == 3:
                resp = send_req("user", "pass", "A"*300)
                if resp in ["OK", "ERROR", "DENIED"]: correct += 1
    finally:
        p.terminate()
        p.wait()

    print(f"SCORE: {correct/total}")

if __name__ == "__main__":
    test()
EOF

    chmod +x /app/evaluate_server.py
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
