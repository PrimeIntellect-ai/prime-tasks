#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make golang patch curl
pip3 install pytest

mkdir -p /home/user/polyglot-build/c_src
mkdir -p /home/user/polyglot-build/go_src

cat << 'EOF' > /home/user/polyglot-build/c_src/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};

    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8081);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(1) {
        new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
        read(new_socket, buffer, 1024);
        char *response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nPOLYGLOT_BACKEND_OK\n";
        write(new_socket, response, strlen(response));
        close(new_socket);
    }
    return 0;
}
EOF

cat << 'EOF' > /home/user/polyglot-build/c_src/Makefile.broken
c_server: main.c
    gcc main.c -o c_server
clean:
    rm -f c_server
EOF

cat << 'EOF' > /home/user/polyglot-build/go_src/proxy.go
package main

import (
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
)

func main() {
	target, err := url.Parse("http://127.0.0.1:9999") // BUG: wrong port
	if err != nil {
		log.Fatal(err)
	}

	proxy := httputil.NewSingleHostReverseProxy(target)

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		r.Header.Set("X-Proxy-Version", "1.0")
		proxy.ServeHTTP(w, r)
	})

	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

cat << 'EOF' > /home/user/polyglot-build/go_src/proxy_fix.patch
--- proxy.go	2023-10-10 10:00:00.000000000 +0000
+++ proxy_fixed.go	2023-10-10 10:01:00.000000000 +0000
@@ -8,7 +8,7 @@
 )

 func main() {
-	target, err := url.Parse("http://127.0.0.1:9999") // BUG: wrong port
+	target, err := url.Parse("http://127.0.0.1:8081")
 	if err != nil {
 		log.Fatal(err)
 	}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
