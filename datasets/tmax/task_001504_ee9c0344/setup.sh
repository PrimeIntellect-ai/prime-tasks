#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server libhiredis-dev gcc make golang curl
pip3 install pytest

service redis-server start || redis-server --daemonize yes

mkdir -p /home/user/app/backend /home/user/app/proxy
cat << 'EOF' > /home/user/app/backend/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <hiredis/hiredis.h>

// TODO: Implement is_valid_release
// Returns 1 if version >= 2.0.0, else 0
int is_valid_release(const char* version) {
    return 0; // REPLACE ME
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};

    redisContext *c = redisConnect("127.0.0.1", 6379);
    if (c == NULL || c->err) {
        printf("Redis error\n");
        return 1;
    }

    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8081);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(1) {
        new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
        int valread = read(new_socket, buffer, 1024);
        if (valread > 0) {
            buffer[valread] = '\0';
            char *sep = strchr(buffer, '|');
            if (sep) {
                *sep = '\0';
                char *version = buffer;
                char *data = sep + 1;
                if (is_valid_release(version)) {
                    redisReply *reply = redisCommand(c, "RPUSH releases:valid %s", data);
                    freeReplyObject(reply);
                } else {
                    redisReply *reply = redisCommand(c, "RPUSH releases:invalid %s", data);
                    freeReplyObject(reply);
                }
            }
        }
        close(new_socket);
    }
    return 0;
}
EOF

cat << 'EOF' > /home/user/app/backend/Makefile
all:
	gcc server.c -o backend_server
EOF

cat << 'EOF' > /home/user/app/proxy/main.go
package main
import (
    "encoding/json"
    "io/ioutil"
    "net/http"
    "net"
)
type Config struct {
    ListenAddr  string `json:"listen_addr"`
    BackendAddr string `json:"backend_addr"`
}
func main() {
    data, _ := ioutil.ReadFile("config.json")
    var cfg Config
    json.Unmarshal(data, &cfg)

    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        body, _ := ioutil.ReadAll(r.Body)
        conn, err := net.Dial("tcp", cfg.BackendAddr)
        if err == nil {
            conn.Write(body)
            conn.Close()
        }
        w.WriteHeader(http.StatusOK)
    })
    http.ListenAndServe(cfg.ListenAddr, nil)
}
EOF

cd /home/user/app/proxy && go build -o proxy_server main.go
echo '{}' > /home/user/app/proxy/config.json

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/app
chmod -R 777 /home/user
