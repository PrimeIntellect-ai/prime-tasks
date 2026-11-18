#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git build-essential
    pip3 install pytest

    mkdir -p /home/user/fast-telemetry/src
    mkdir -p /home/user/fast-telemetry/include
    mkdir -p /home/user/fast-telemetry/tests

    cd /home/user/fast-telemetry
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    cat << 'EOF' > include/telemetry.h
#ifndef TELEMETRY_H
#define TELEMETRY_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

typedef struct {
    int32_t* data;
    size_t head;
    size_t tail;
    size_t max;
    bool full;
} CircularDeltaBuffer;

typedef struct {
    int max_buffer_size;
} Config;

extern void (*write_sink)(const char* data);

void compute_deltas(const int32_t* curr, const int32_t* prev, int32_t* out, size_t len);
bool push_buffer(CircularDeltaBuffer* cb, int32_t val);
bool pop_buffer(CircularDeltaBuffer* cb, int32_t* val);
int parse_config(const char* filepath, Config* cfg);
void flush_telemetry(const char* message);

#endif
EOF

    cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-Iinclude -g -Wall

all: libtelemetry.a

libtelemetry.a: src/delta_calc.o src/buffer.o src/config.o
	ar rcs $@ $^

test: tests/test_main
	./tests/test_main

tests/test_main: tests/test_main.c libtelemetry.a
	$(CC) $(CFLAGS) -o $@ $^

clean:
	rm -f src/*.o *.a tests/test_main
EOF

    git add .
    git commit -m "Initial commit"

    git checkout -b pr-104-fast-delta

    cat << 'EOF' > src/delta_calc.c
#include "telemetry.h"

void compute_deltas(const int32_t* curr, const int32_t* prev, int32_t* out, size_t len) {
    for (size_t i = 0; i < len; i++) {
        __asm__ __volatile__(
            "movl %1, %%eax;\n"
            "addl %2, %%eax;\n" // BROKEN: should be subl
            "movl %%eax, %0;\n"
            : "=m" (out[i])
            : "m" (curr[i]), "m" (prev[i])
            : "%eax"
        );
    }
}
EOF

    cat << 'EOF' > src/buffer.c
#include "telemetry.h"

bool push_buffer(CircularDeltaBuffer* cb, int32_t val) {
    // TODO: implement circular push
    return false;
}

bool pop_buffer(CircularDeltaBuffer* cb, int32_t* val) {
    // TODO: implement circular pop
    return false;
}
EOF

    cat << 'EOF' > src/config.c
#include "telemetry.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int parse_config(const char* filepath, Config* cfg) {
    // TODO: Parse KEY=VALUE and set cfg->max_buffer_size
    return -1;
}
EOF

    cat << 'EOF' > tests/test_main.c
#include "telemetry.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>
#include <stdlib.h>

void default_sink(const char* data) {
    FILE* f = fopen("/etc/telemetry.log", "a");
    if (!f) {
        printf("SINK ERROR\n");
        exit(1);
    }
    fprintf(f, "%s", data);
    fclose(f);
}

void (*write_sink)(const char* data) = default_sink;

void flush_telemetry(const char* message) {
    write_sink(message);
}

int main() {
    // Test deltas
    int32_t curr[] = {10, 25, 30};
    int32_t prev[] = {5, 10, 35};
    int32_t out[3] = {0};
    compute_deltas(curr, prev, out, 3);
    if(out[0] != 5 || out[1] != 15 || out[2] != -5) {
        printf("DELTA TEST FAILED\n");
        return 1;
    }

    // Test buffer
    int32_t buf_data[3];
    CircularDeltaBuffer cb = {buf_data, 0, 0, 3, false};
    assert(push_buffer(&cb, 10) == true);
    assert(push_buffer(&cb, 20) == true);
    assert(push_buffer(&cb, 30) == true);
    assert(push_buffer(&cb, 40) == false);

    int32_t v;
    assert(pop_buffer(&cb, &v) == true && v == 10);
    assert(pop_buffer(&cb, &v) == true && v == 20);

    // Test config
    FILE* cf = fopen("test.cfg", "w");
    fprintf(cf, "MAX_BUFFER_SIZE=1024\n");
    fclose(cf);

    Config cfg;
    assert(parse_config("test.cfg", &cfg) == 0);
    assert(cfg.max_buffer_size == 1024);

    // Test sink
    flush_telemetry("test-data");
    // The mock output array should be checked here by the agent if they wrote it correctly

    printf("ALL TESTS PASSED\n");
    return 0;
}
EOF

    git add .
    git commit -m "PR: Add fast delta and buffer"

    git checkout master

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
