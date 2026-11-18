#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make netcat-openbsd gdb strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/log_service

    cat << 'EOF' > /home/user/log_service/logd.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>

pthread_mutex_t log_mutex = PTHREAD_MUTEX_INITIALIZER;

void *handle_client(void *arg) {
    int client_sock = *(int *)arg;
    free(arg);
    char buffer[512] = {0};

    int n = read(client_sock, buffer, sizeof(buffer)-1);
    if (n <= 0) {
        close(client_sock);
        return NULL;
    }

    pthread_mutex_lock(&log_mutex);
    char level[16] = {0};
    char message[256] = {0};

    // Buggy parser
    int parsed = sscanf(buffer, "[%15[^]]] %[^\n]", level, message);
    if (parsed != 2) {
        fprintf(stderr, "Invalid log format\n");
        // DEADLOCK HERE: missing pthread_mutex_unlock(&log_mutex);
        close(client_sock);
        return NULL;
    }

    if (message[0] == '[') {
        // Bug: parser rejects messages that start with '['
        fprintf(stderr, "Invalid message content\n");
        pthread_mutex_unlock(&log_mutex);
        close(client_sock);
        return NULL;
    }

    FILE *f = fopen("server.log", "a");
    if (f) {
        fprintf(f, "Logged [%s]: %s\n", level, message);
        fclose(f);
    }
    pthread_mutex_unlock(&log_mutex);

    char *resp = "OK\n";
    write(client_sock, resp, strlen(resp));
    close(client_sock);
    return NULL;
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

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
    address.sin_port = htons(8888);

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
            continue;
        }

        pthread_t thread_id;
        int *client_sock = malloc(sizeof(int));
        *client_sock = new_socket;

        if(pthread_create(&thread_id, NULL, handle_client, (void*)client_sock) < 0) {
            perror("could not create thread");
            free(client_sock);
            continue;
        }
        pthread_detach(thread_id);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/log_service/Makefile
CC=gcc
CFLAGS=-Wall -pthread

all: logd

logd: logd.c
	$(CC) $(CFLAGS) -o logd logd.c

test: logd
	./test.sh

clean:
	rm -f logd server.log
EOF

    cat << 'EOF' > /home/user/log_service/test.sh
#!/bin/bash
rm -f server.log
./logd > /dev/null 2>&1 &
SERVER_PID=$!
sleep 1

echo "[INFO] Normal message" | nc localhost 8888 > /dev/null
echo "MALFORMED" | nc localhost 8888 > /dev/null
timeout 2 echo "[WARN] Second message" | nc localhost 8888 > /dev/null
if [ $? -ne 0 ]; then 
    echo "Test failed: server deadlocked on MALFORMED message"
    kill $SERVER_PID
    exit 1
fi

timeout 2 echo "[INFO] [System] started" | nc localhost 8888 > /dev/null
if ! grep -q "Logged \[INFO\]: \[System\] started" server.log 2>/dev/null; then
    echo "Test failed: message starting with '[' was rejected or parsed incorrectly"
    kill $SERVER_PID
    exit 1
fi

kill $SERVER_PID
echo "All tests passed!"
exit 0
EOF
    chmod +x /home/user/log_service/test.sh

    chmod -R 777 /home/user
