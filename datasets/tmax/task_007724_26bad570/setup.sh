#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make libasan6
pip3 install pytest

mkdir -p /home/user/py_ext
cd /home/user/py_ext

cat << 'EOF' > python_mock.h
#ifndef PYTHON_MOCK_H
#define PYTHON_MOCK_H

#include <stdint.h>
#include <string.h>

typedef struct {
    char* data;
} PyObject;

static inline char* PyString_AsString(PyObject* obj) {
    return obj->data;
}

static inline char* PyUnicode_AsUTF8(PyObject* obj) {
    return obj->data; // Mock implementation for test
}

#endif
EOF

cat << 'EOF' > fast_req.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "python_mock.h"

// 1. Memory Safety Issue
char* parse_header(const char* input) {
    if (!input) return NULL;
    int len = strlen(input);
    char* buffer = (char*)malloc(len); // BUG: off by one, needs len + 1
    if (len > 100) {
        return NULL; // BUG: memory leak, buffer not freed
    }
    strcpy(buffer, input);
    return buffer;
}

// 2. Conditional Build (Py2/Py3)
char* extract_string(PyObject* obj) {
    // TODO: Implement #if PY_MAJOR_VERSION >= 3 conditional logic
    // Currently only Py2 logic
    return PyString_AsString(obj);
}

// 3. Rate Limiting (Token Bucket)
typedef struct {
    uint64_t tokens;
    uint64_t last_update;
} Bucket;

Bucket clients[100];

int check_rate_limit(uint32_t client_id, uint64_t current_time_ms) {
    // TODO: Implement token bucket
    // Capacity = 10, Refill = 1 per 100ms
    if (client_id >= 100) return 0;
    return 1; // Allow everything initially
}
EOF

cp fast_req.c fast_req.c.orig

cat << 'EOF' > test_runner.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "python_mock.h"

char* parse_header(const char* input);
char* extract_string(PyObject* obj);
int check_rate_limit(uint32_t client_id, uint64_t current_time_ms);

void test_memory() {
    char* res1 = parse_header("short");
    assert(strcmp(res1, "short") == 0);
    free(res1);

    char long_str[150];
    memset(long_str, 'A', 149);
    long_str[149] = '\0';
    char* res2 = parse_header(long_str);
    assert(res2 == NULL);
}

void test_rate_limit() {
    // client 1: fast burst
    for(int i=0; i<10; i++) {
        assert(check_rate_limit(1, 1000) == 1);
    }
    assert(check_rate_limit(1, 1000) == 0); // 11th should fail

    // wait 300ms -> 3 tokens
    assert(check_rate_limit(1, 1300) == 1);
    assert(check_rate_limit(1, 1300) == 1);
    assert(check_rate_limit(1, 1300) == 1);
    assert(check_rate_limit(1, 1300) == 0);
}

int main() {
    test_memory();
    test_rate_limit();

    PyObject obj;
    obj.data = "mockdata";
    char* s = extract_string(&obj);
    assert(strcmp(s, "mockdata") == 0);

    printf("ALL TESTS PASSED\n");
    return 0;
}
EOF

cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-g -Wall -fsanitize=address

all: test_ext

test_ext: fast_req.c test_runner.c
	$(CC) $(CFLAGS) -DPY_MAJOR_VERSION=3 fast_req.c test_runner.c -o test_ext

clean:
	rm -f test_ext
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
