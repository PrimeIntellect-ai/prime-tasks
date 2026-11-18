#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make netcat-openbsd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create app directory
    mkdir -p /app/net-aggregator-1.2.0

    cat << 'EOF' > /app/net-aggregator-1.2.0/Makefile
CC=gcc
CFLAGS=-O2

all: net-aggregator

net-aggregator: main.o parser.o
	$(CC) $(CFLAGS) -o net-aggregator main.o parser.o

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

parser.o: parser.c
	$(CC) $(CFLAGS) -c parser.c

clean:
	rm -f *.o net-aggregator
EOF

    cat << 'EOF' > /app/net-aggregator-1.2.0/parser.h
#ifndef PARSER_H
#define PARSER_H
void build_log_string(const char* input, char* output);
#endif
EOF

    cat << 'EOF' > /app/net-aggregator-1.2.0/parser.c
#include <string.h>
#include "parser.h"

void build_log_string(const char* input, char* output) {
    output[0] = '\0';
    for(int i = 0; input[i] != '\0'; i++) {
        char temp[2] = {input[i], '\0'};
        strcat(output, temp); // Deliberate O(N^2) bottleneck
    }
}
EOF

    cat << 'EOF' > /app/net-aggregator-1.2.0/main.c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include "parser.h"

void* dummy_thread(void* arg) {
    return NULL;
}

int main(int argc, char** argv) {
    char* conf = getenv("AGGREGATOR_CONF");
    if (!conf) {
        fprintf(stderr, "AGGREGATOR_CONF not set\n");
        return 1;
    }

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in serv_addr;
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(8088);
    inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr);

    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        fprintf(stderr, "Connection to 127.0.0.1:8088 failed\n");
        return 1;
    }
    close(sock);

    pthread_t thread;
    pthread_create(&thread, NULL, dummy_thread, NULL);
    pthread_join(thread, NULL);

    if (argc >= 3 && strcmp(argv[1], "--test-run") == 0) {
        FILE* f = fopen(argv[2], "r");
        if (!f) return 1;
        char line[1024];
        char output[1024];
        while (fgets(line, sizeof(line), f)) {
            build_log_string(line, output);
        }
        fclose(f);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/start_metrics.sh
#!/bin/bash
source /home/user/metrics.env
/home/user/bin/net-aggregator --test-run /home/user/test_logs.txt
EOF
    chmod +x /home/user/start_metrics.sh

    echo "junk line 1" > /home/user/messy_config_dump.txt
    echo "... [PROD_KEY] UUID=f47ac10b-58cc-4372-a567-0e02b2c3d479 ..." >> /home/user/messy_config_dump.txt
    echo "junk line 2" >> /home/user/messy_config_dump.txt

    # Generate 50,000 lines of logs
    python3 -c '
with open("/home/user/test_logs.txt", "w") as f:
    for i in range(50000):
        f.write(f"INFO 2023-10-01T12:00:00Z user_{i} logged in from 192.168.1.100\n")
'

    chmod -R 777 /app
    chmod -R 777 /home/user
