#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git build-essential espeak
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create the audio file
    mkdir -p /app
    espeak -w /app/incident_report.wav "The production server timezone variable must be set exactly to Europe slash Berlin to avoid the cache invalidation issue."

    # Setup the Git repository
    mkdir -p /home/user/audiostreamer/src
    cd /home/user/audiostreamer

    cat << 'EOF' > Makefile
all:
	gcc src/server.c src/time_utils.c -o server -lpthread
EOF

    cat << 'EOF' > src/time_utils.c
#include <time.h>

void normalize_timestamp() {
    struct tm t = {0};
    t.tm_year = 120;
    t.tm_mon = 0;
    t.tm_mday = 1;
    // t.tm_isdst = -1; // Missing initialization

    time_t t1 = mktime(&t);
    int diff = 1;
    while (diff > 0) {
        if (t.tm_isdst == -1) {
            diff = 0;
        } else {
            t.tm_isdst = (t.tm_isdst == 0) ? 1 : 0;
            mktime(&t);
        }
    }
}
EOF

    cat << 'EOF' > src/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
// #include <pthread.h> // Missing include

extern void normalize_timestamp();

void *handle_client(void *arg) {
    int conn_socket = *(int *)arg;
    free(arg);
    char buffer[1024] = {0};
    read(conn_socket, buffer, 1024);

    char *auth = getenv("AUTH_TOKEN");
    char *tz = getenv("SERVER_TZ");

    if (auth && strstr(buffer, auth) != NULL) {
        normalize_timestamp();
        char response[512];
        sprintf(response, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\": \"ok\", \"timezone\": \"%s\"}\n", tz ? tz : "unknown");
        write(conn_socket, response, strlen(response));
    } else {
        char *response = "HTTP/1.1 401 Unauthorized\r\n\r\n";
        write(conn_socket, response, strlen(response));
    }
    close(conn_socket);
    return NULL;
}

int main() {
    int server_fd;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) exit(EXIT_FAILURE);
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) exit(EXIT_FAILURE);
    if (listen(server_fd, 3) < 0) exit(EXIT_FAILURE);

    while(1) {
        int *conn_sockt = malloc(sizeof(int));
        *conn_sockt = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
        pthread_t thread_id;
        pthread_create(&thread_id, NULL, handle_client, (void*)conn_socket);
        pthread_detach(thread_id);
    }
    return 0;
}
EOF

    git init
    git config user.email "dev@audiostreamer.local"
    git config user.name "Dev"
    git add Makefile src/
    git commit -m "Initial commit"

    echo '#define DEFAULT_AUTH_TOKEN "f8a92b1c4e7d3w5q"' > config.h.backup
    git add config.h.backup
    git commit -m "Add backup config"

    git rm config.h.backup
    git commit -m "Remove backup config"

    echo "Update 1" > README.md
    git add README.md
    git commit -m "Update README"

    echo "Update 2" >> README.md
    git add README.md
    git commit -m "Update README again"

    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
