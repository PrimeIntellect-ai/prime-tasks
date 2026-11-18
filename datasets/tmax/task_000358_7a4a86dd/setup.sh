#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/parser.h
#ifndef PARSER_H
#define PARSER_H

typedef struct {
    char *method;
    char *uri;
    char *version;
} Request;

typedef struct {
    Request *requests;
    int count;
    int capacity;
} RequestList;

RequestList* parse_requests(const char *filename);
void free_requests(RequestList *list);

#endif
EOF

    cat << 'EOF' > /home/user/project/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser.h"

RequestList* parse_requests(const char *filename) {
    FILE *file = fopen(filename, "r");
    if (!file) return NULL;

    RequestList *list = malloc(sizeof(RequestList));
    list->capacity = 10;
    list->count = 0;
    list->requests = malloc(sizeof(Request) * list->capacity);

    char line[256];
    // BUG: The pointers are assigned directly to the stack buffer 'line'
    // or parts of it via strtok, which will be overwritten on the next loop.
    while (fgets(line, sizeof(line), file)) {
        if (list->count >= list->capacity) {
            list->capacity *= 2;
            list->requests = realloc(list->requests, sizeof(Request) * list->capacity);
        }

        char *method = strtok(line, " \t\r\n");
        char *uri = strtok(NULL, " \t\r\n");
        char *version = strtok(NULL, " \t\r\n");

        if (method && uri && version) {
            list->requests[list->count].method = method; // BUG
            list->requests[list->count].uri = uri;       // BUG
            list->requests[list->count].version = version; // BUG
            list->count++;
        }
    }

    fclose(file);
    return list;
}

void free_requests(RequestList *list) {
    if (!list) return;
    // Missing free logic for duplicated strings (since they weren't duplicated)
    free(list->requests);
    free(list);
}
EOF

    cat << 'EOF' > /home/user/project/main.c
#include <stdio.h>
#include "parser.h"

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("Usage: %s <log_file>\n", argv[0]);
        return 1;
    }

    RequestList *list = parse_requests(argv[1]);
    if (!list) {
        printf("Failed to parse file.\n");
        return 1;
    }

    for (int i = 0; i < list->count; i++) {
        printf("Method: %s, URI: %s, Version: %s\n", 
               list->requests[i].method, 
               list->requests[i].uri, 
               list->requests[i].version);
    }

    free_requests(list);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/Makefile
CC = gcc
CFLAGS = -Wall -Wextra -I.

all: http_parser

http_parser: main.o parser.o
	$(CC) $(CFLAGS) -o http_parser main.o parser.o

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

parser.o: parser.c
	$(CC) $(CFLAGS) -c parser.c

clean:
	rm -f *.o http_parser
EOF

    cat << 'EOF' > /home/user/project/requests.log
GET /api/v1/users HTTP/1.1
POST /api/v1/login HTTP/1.1
PUT /api/v1/settings HTTP/1.0
DELETE /api/v1/users/123 HTTP/1.1
GET /health HTTP/1.1
EOF

    chown -R user:user /home/user/project
    chmod -R 777 /home/user
