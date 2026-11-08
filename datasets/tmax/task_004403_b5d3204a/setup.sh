#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev nginx curl
    pip3 install pytest numpy

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/broker.py
import socket
import struct
import numpy as np

def start_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind(('127.0.0.1', 9000))
    server.listen(5)
    np.random.seed(42)
    x = np.random.uniform(0, 10, 1000).astype(np.float32)
    y = (2.5 * x + np.random.normal(0, 2, 1000)).astype(np.float32)
    data = struct.pack(f'{len(x)}f', *x) + struct.pack(f'{len(y)}f', *y)

    while True:
        conn, _ = server.accept()
        conn.sendall(data)
        conn.close()

if __name__ == "__main__":
    start_server()
EOF

    cat << 'EOF' > /home/user/app/engine.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <math.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>

#define NUM_POINTS 1000
#define NUM_THREADS 4
#define BOOTSTRAP_ITERS 10000

float x_data[NUM_POINTS];
float y_data[NUM_POINTS];
float slopes[BOOTSTRAP_ITERS];

// Shared global variables to fix
float sum_x = 0, sum_y = 0, sum_xy = 0, sum_xx = 0;
pthread_mutex_t lock;

typedef struct {
    int start_iter;
    int end_iter;
    unsigned int seed;
} ThreadData;

void* bootstrap_worker(void* arg) {
    ThreadData* td = (ThreadData*)arg;
    for (int i = td->start_iter; i < td->end_iter; i++) {
        float loc_sum_x = 0, loc_sum_y = 0, loc_sum_xy = 0, loc_sum_xx = 0;
        for (int j = 0; j < NUM_POINTS; j++) {
            int idx = rand_r(&td->seed) % NUM_POINTS;
            loc_sum_x += x_data[idx];
            loc_sum_y += y_data[idx];
            loc_sum_xy += x_data[idx] * y_data[idx];
            loc_sum_xx += x_data[idx] * x_data[idx];
        }
        float slope = (NUM_POINTS * loc_sum_xy - loc_sum_x * loc_sum_y) / 
                      (NUM_POINTS * loc_sum_xx - loc_sum_x * loc_sum_x);
        slopes[i] = slope;

        // BUG: Non-deterministic floating point reduction
        pthread_mutex_lock(&lock);
        sum_x += loc_sum_x;
        sum_y += loc_sum_y;
        sum_xy += loc_sum_xy;
        sum_xx += loc_sum_xx;
        pthread_mutex_unlock(&lock);
    }
    return NULL;
}

int compare_floats(const void* a, const void* b) {
    float fa = *(const float*)a;
    float fb = *(const float*)b;
    return (fa > fb) - (fa < fb);
}

void run_server() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(5000);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while (1) {
        int new_socket = accept(server_fd, NULL, NULL);
        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);

        if (strncmp(buffer, "GET /analyze", 12) == 0) {
            // Fetch data
            int data_sock = socket(AF_INET, SOCK_STREAM, 0);
            struct sockaddr_in data_serv;
            data_serv.sin_family = AF_INET;
            data_serv.sin_port = htons(9000);
            inet_pton(AF_INET, "127.0.0.1", &data_serv.sin_addr);
            connect(data_sock, (struct sockaddr *)&data_serv, sizeof(data_serv));

            read(data_sock, x_data, NUM_POINTS * sizeof(float));
            read(data_sock, y_data, NUM_POINTS * sizeof(float));
            close(data_sock);

            sum_x = 0; sum_y = 0; sum_xy = 0; sum_xx = 0;
            pthread_mutex_init(&lock, NULL);
            pthread_t threads[NUM_THREADS];
            ThreadData td[NUM_THREADS];

            for (int i = 0; i < NUM_THREADS; i++) {
                td[i].start_iter = i * (BOOTSTRAP_ITERS / NUM_THREADS);
                td[i].end_iter = (i + 1) * (BOOTSTRAP_ITERS / NUM_THREADS);
                td[i].seed = 42 + i;
                pthread_create(&threads[i], NULL, bootstrap_worker, &td[i]);
            }

            for (int i = 0; i < NUM_THREADS; i++) {
                pthread_join(threads[i], NULL);
            }

            qsort(slopes, BOOTSTRAP_ITERS, sizeof(float), compare_floats);
            float lower = slopes[(int)(BOOTSTRAP_ITERS * 0.025)];
            float upper = slopes[(int)(BOOTSTRAP_ITERS * 0.975)];

            char response[512];
            sprintf(response, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n[%.6f, %.6f]", lower, upper);
            write(new_socket, response, strlen(response));
        } else {
            char* err = "HTTP/1.1 404 Not Found\r\n\r\n";
            write(new_socket, err, strlen(err));
        }
        close(new_socket);
    }
}

int main() {
    run_server();
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
