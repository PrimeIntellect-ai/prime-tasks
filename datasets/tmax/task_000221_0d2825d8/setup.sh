#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libcurl4-openssl-dev
    pip3 install pytest

    mkdir -p /home/user/build_telemetry

    cat << 'EOF' > /home/user/build_telemetry/Makefile
CC = gcc
CFLAGS = -Wall -g

all: build_reporter

build_reporter: build_reporter.o cmap.o
	$(CC) $(CFLAGS) -o build_reporter build_reporter.o cmap.o

build_reporter.o: build_reporter.c
	$(CC) $(CFLAGS) -c build_reporter.c

cmap.o: cmap.c
	$(CC) $(CFLAGS) -c cmap.c

clean:
	rm -f *.o build_reporter
EOF

    cat << 'EOF' > /home/user/build_telemetry/cmap.h
#ifndef CMAP_H
#define CMAP_H

typedef struct CMapNode {
    char *key;
    int value;
    struct CMapNode *next;
} CMapNode;

typedef struct {
    CMapNode **buckets;
    int capacity;
} CMap;

CMap* cmap_create(int capacity);
void cmap_insert(CMap *map, const char *key, int value);
void cmap_free(CMap *map);

#endif
EOF

    cat << 'EOF' > /home/user/build_telemetry/cmap.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "cmap.h"

CMap* cmap_create(int capacity) {
    CMap *map = malloc(sizeof(CMap));
    map->capacity = capacity;
    map->buckets = calloc(capacity, sizeof(CMapNode*));
    return map;
}

void cmap_insert(CMap *map, const char *key, int value) {
    int index = 0;
    for (int i = 0; key[i] != '\0'; i++) {
        index = (index + key[i]) % map->capacity;
    }

    CMapNode *node = malloc(sizeof(CMapNode));
    // BUG: Missing memory allocation for key. strcpy will segfault because node->key is uninitialized.
    // FIX: node->key = strdup(key); OR node->key = malloc(strlen(key) + 1); strcpy(node->key, key);
    strcpy(node->key, key); 
    node->value = value;
    node->next = map->buckets[index];
    map->buckets[index] = node;
}

void cmap_free(CMap *map) {
    for (int i = 0; i < map->capacity; i++) {
        CMapNode *curr = map->buckets[i];
        while (curr) {
            CMapNode *temp = curr;
            curr = curr->next;
            free(temp->key);
            free(temp);
        }
    }
    free(map->buckets);
    free(map);
}
EOF

    cat << 'EOF' > /home/user/build_telemetry/build_reporter.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <curl/curl.h>
#include "cmap.h"

int main(void) {
    CMap *metrics = cmap_create(10);

    char buffer[50];

    // Simulating collecting metrics
    strcpy(buffer, "apk_size");
    cmap_insert(metrics, buffer, 15400230);

    strcpy(buffer, "dex_count");
    cmap_insert(metrics, buffer, 3);

    strcpy(buffer, "lint_errors");
    cmap_insert(metrics, buffer, 12);

    // Build simple JSON
    char json_payload[256];
    snprintf(json_payload, sizeof(json_payload), 
             "{\"apk_size\":%d,\"dex_count\":%d,\"lint_errors\":%d}", 
             15400230, 3, 12);

    CURL *curl;
    CURLcode res;

    curl_global_init(CURL_GLOBAL_ALL);
    curl = curl_easy_init();
    if(curl) {
        struct curl_slist *headers = NULL;
        headers = curl_slist_append(headers, "Content-Type: application/json");

        curl_easy_setopt(curl, CURLOPT_URL, "http://localhost:8080/report");
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, json_payload);

        res = curl_easy_perform(curl);
        if(res != CURLE_OK)
            fprintf(stderr, "curl_easy_perform() failed: %s\n", curl_easy_strerror(res));

        curl_easy_cleanup(curl);
        curl_slist_free_all(headers);
    }
    curl_global_cleanup();
    cmap_free(metrics);

    return 0;
}
EOF

    cat << 'EOF' > /home/user/build_telemetry/server.py
import http.server
import socketserver
import json
import os

PORT = 8080

class TelemetryHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)

        try:
            data = json.loads(post_data.decode('utf-8'))
            with open('/home/user/build_telemetry/telemetry_success.json', 'w') as f:
                json.dump(data, f)

            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Success")
        except Exception as e:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(str(e).encode())

with socketserver.TCPServer(("", PORT), TelemetryHandler) as httpd:
    httpd.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
