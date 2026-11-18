#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make valgrind
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/libdataparser.h
#ifndef LIBDATAPARSER_H
#define LIBDATAPARSER_H

typedef struct {
    char* key;
    char* value;
} KVPair;

typedef struct {
    KVPair* pairs;
    int count;
} ParsedData;

ParsedData* parse_payload(const char* payload);
void free_parsed_data(ParsedData* data);

#endif
EOF

    cat << 'EOF' > /home/user/project/libdataparser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "libdataparser.h"

ParsedData* parse_payload(const char* payload) {
    ParsedData* data = malloc(sizeof(ParsedData));
    data->count = 0;
    data->pairs = NULL;

    char* payload_copy = strdup(payload);
    char* token = strtok(payload_copy, ",");

    while (token != NULL) {
        data->pairs = realloc(data->pairs, sizeof(KVPair) * (data->count + 1));

        char* colon = strchr(token, ':');
        if (colon != NULL) {
            *colon = '\0';
            data->pairs[data->count].key = strdup(token);
            data->pairs[data->count].value = strdup(colon + 1);
            data->count++;
        }
        token = strtok(NULL, ",");
    }

    free(payload_copy);
    return data;
}

void free_parsed_data(ParsedData* data) {
    if (!data) return;
    for (int i = 0; i < data->count; i++) {
        free(data->pairs[i].key);
        free(data->pairs[i].value);
    }
    free(data->pairs);
    free(data);
}
EOF

    cat << 'EOF' > /home/user/project/main.c
#include <stdio.h>
#include "libdataparser.h"

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Usage: %s <payload>\n", argv[0]);
        return 1;
    }

    ParsedData* data = parse_payload(argv[1]);

    for (int i = 0; i < data->count; i++) {
        printf("Key: %s | Value: %s\n", data->pairs[i].key, data->pairs[i].value);
    }

    // MISSING: free_parsed_data(data);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/Makefile
all: app

lib: libdataparser.c
	gcc -shared -fPIC libdataparser.c -o libdataparser.so

app: main.c
	gcc main.c -o app -ldataparser
EOF

    chmod -R 777 /home/user
