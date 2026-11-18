#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make valgrind
pip3 install pytest

mkdir -p /home/user/workspace/librest_parser/src
mkdir -p /home/user/workspace/librest_parser/include
mkdir -p /home/user/workspace/librest_parser/tests

cat << 'EOF' > /home/user/workspace/librest_parser/Makefile
CC = gcc
CFLAGS = -Wall -g -Iinclude
LDFLAGS = -shared

all: librest_parser.so

librest_parser.so: src/parser.o src/string_buf.o
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	rm -f src/*.o *.so run_tests test_results.log
EOF

cat << 'EOF' > /home/user/workspace/librest_parser/include/string_buf.h
#ifndef STRING_BUF_H
#define STRING_BUF_H

#include <stddef.h>

// BUG 1: Global variable defined in header causes multiple definition errors
int global_alloc_count = 0;

typedef struct {
    char *data;
    size_t length;
    size_t capacity;
} string_buf_t;

string_buf_t* string_buf_new(void);
void string_buf_append(string_buf_t *buf, const char *str, size_t len);
void string_buf_free(string_buf_t *buf);

#endif
EOF

cat << 'EOF' > /home/user/workspace/librest_parser/include/parser.h
#ifndef PARSER_H
#define PARSER_H

#include "string_buf.h"

typedef struct {
    string_buf_t *method;
    string_buf_t *path;
    int error_flag;
} rest_request_t;

rest_request_t* rest_request_new(void);
void rest_request_free(rest_request_t *req);
int parse_rest_request(const char *raw_data, rest_request_t *req);

#endif
EOF

cat << 'EOF' > /home/user/workspace/librest_parser/src/string_buf.c
#include "string_buf.h"
#include <stdlib.h>
#include <string.h>

string_buf_t* string_buf_new(void) {
    string_buf_t *buf = malloc(sizeof(string_buf_t));
    buf->data = malloc(16);
    buf->capacity = 16;
    buf->length = 0;
    buf->data[0] = '\0';
    return buf;
}

void string_buf_append(string_buf_t *buf, const char *str, size_t len) {
    if (buf->length + len + 1 > buf->capacity) {
        buf->capacity = (buf->length + len + 1) * 2;
        buf->data = realloc(buf->data, buf->capacity);
    }
    memcpy(buf->data + buf->length, str, len);
    buf->length += len;
    buf->data[buf->length] = '\0';
}

void string_buf_free(string_buf_t *buf) {
    if (buf) {
        free(buf->data);
        // BUG 2: missing free(buf) - causes memory leak
    }
}
EOF

cat << 'EOF' > /home/user/workspace/librest_parser/src/parser.c
#include "parser.h"
#include <string.h>
#include <stdlib.h>

rest_request_t* rest_request_new(void) {
    rest_request_t *req = malloc(sizeof(rest_request_t));
    req->method = string_buf_new();
    req->path = string_buf_new();
    req->error_flag = 0;
    return req;
}

void rest_request_free(rest_request_t *req) {
    if (req) {
        string_buf_free(req->method);
        string_buf_free(req->path);
        free(req);
    }
}

int parse_rest_request(const char *raw_data, rest_request_t *req) {
    const char *ptr = raw_data;
    const char *space = strchr(ptr, ' ');
    if (!space) return -1;

    if (strncmp(ptr, "GET", 3) != 0 && strncmp(ptr, "POST", 4) != 0) {
        // BUG 3: Returns error but leaks memory if handled incorrectly by caller, 
        // though strictly memory issue might just be in the struct usage. Let's just return error here.
        return -1;
    }

    string_buf_append(req->method, ptr, space - ptr);
    ptr = space + 1;

    space = strchr(ptr, ' ');
    if (!space) return -1;

    string_buf_append(req->path, ptr, space - ptr);
    ptr = space + 1;

    const char *rnrn = strstr(ptr, "\r\n\r\n");
    if (!rnrn) return -1;

    // Check headers for colon
    const char *header_start = strstr(ptr, "\r\n");
    if (header_start && header_start < rnrn) {
        header_start += 2;
        if (header_start < rnrn) {
             const char *colon = strchr(header_start, ':');
             if (!colon || colon > rnrn) return -1;
        }
    }

    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
