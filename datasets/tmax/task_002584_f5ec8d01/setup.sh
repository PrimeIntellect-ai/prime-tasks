#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /app/vendor/miniscript

    cat << 'EOF' > /app/vendor/miniscript/miniscript.c
#include <string.h>
#include <math.h>

int evaluate_rule(const char* script, const char* input_data) {
    // Dummy math operation to force the need for -lm
    double dummy = pow(2.0, 3.0);
    if (dummy < 0) return -1;

    // Basic stub logic to satisfy the verifier's expected outputs
    if (strstr(script, "malicious") && strstr(input_data, "malicious")) return 1;
    if (strstr(script, "len(input) > 5") && strlen(input_data) > 5) return 1;
    if (strstr(script, "admin") && strstr(input_data, "admin")) return 1;

    return 0;
}
EOF

    cat << 'EOF' > /app/vendor/miniscript/Makefile
CC = gcc
CFLAGS = -fPIC -Wall -Werror -Wno-unnused
LDFLAGS = -shared

all: libminiscript.so

libminiscript.so: miniscript.o
	$(CC) $(LDFLAGS) -o $@ $^

miniscript.o: miniscript.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o *.so
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
