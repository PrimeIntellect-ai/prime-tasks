#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make netcat-openbsd
pip3 install pytest

mkdir -p /home/user
mkdir -p /app/libtcp-1.0

# Create data.csv
cat << 'EOF' > /home/user/data.csv
X,Y
EOF
for i in $(seq 1 100); do
    echo "$i.0,$(echo "$i * 2" | bc).0" >> /home/user/data.csv
done

# Create train.c
cat << 'EOF' > /home/user/train.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    FILE *f = fopen("data.csv", "r");
    if (!f) return 1;
    char line[256];
    fgets(line, sizeof(line), f); // skip header
    float data_x[100], data_y[100];
    for (int i=0; i<100; i++) {
        fscanf(f, "%f,%f", &data_x[i], &data_y[i]);
    }
    fclose(f);

    // BUG: Computing min/max over the full 100 rows
    float min = data_x[0], max = data_x[0];
    for (int i=0; i<100; i++) {
        if (data_x[i] < min) min = data_x[i];
        if (data_x[i] > max) max = data_x[i];
    }

    float scaled_x[80], train_y[80];
    for (int i=0; i<80; i++) {
        scaled_x[i] = (data_x[i] - min) / (max - min);
        train_y[i] = data_y[i];
    }

    float w = 0.0, b = 0.0;
    float lr = 0.1;
    for (int epoch=0; epoch<1000; epoch++) {
        float dw = 0, db = 0;
        for (int i=0; i<80; i++) {
            float pred = w * scaled_x[i] + b;
            float err = pred - train_y[i];
            dw += err * scaled_x[i];
            db += err;
        }
        w -= lr * dw / 80.0;
        b -= lr * db / 80.0;
    }

    f = fopen("model.weights", "w");
    fprintf(f, "%f\n%f\n%f\n%f\n", w, b, min, max);
    fclose(f);
    return 0;
}
EOF

# Create libtcp-1.0
cat << 'EOF' > /app/libtcp-1.0/tcp_server.h
#ifndef TCP_SERVER_H
#define TCP_SERVER_H

void start_server(int port, void (*handler)(const char* req, char* resp_buf));

#endif
EOF

cat << 'EOF' > /app/libtcp-1.0/tcp_server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include "tcp_server.h"

void start_server(int port, void (*handler)(const char* req, char* resp_buf)) {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};
    char resp[1024] = {0};

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) exit(EXIT_FAILURE);
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) exit(EXIT_FAILURE);

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) exit(EXIT_FAILURE);
    if (listen(server_fd, 3) < 0) exit(EXIT_FAILURE);

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) continue;
        int valread = read(new_socket, buffer, 1024);
        if (valread > 0) {
            buffer[valread] = '\0';
            handler(buffer, resp);
            send(new_socket, resp, strlen(resp), 0);
        }
        close(new_socket);
    }
}
EOF

cat << 'EOF' > /app/libtcp-1.0/Makefile
CC = gcc-99
CFLAGS = -Wall -O2

all: libtcp.a

libtcp.a: tcp_server.o
	ar rcs $@ $^

tcp_server.o: tcp_server.c tcp_server.h
	$(CC) $(CFLAGS) -c tcp_server.c

clean:
	rm -f *.o *.a
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user /app/libtcp-1.0
chmod -R 777 /home/user /app/libtcp-1.0
