#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        build-essential \
        bash-builtins \
        socat \
        jq \
        curl
    pip3 install pytest

    mkdir -p /app/libmathops-1.2.0
    mkdir -p /app/pr-104

    # Create libmathops files
    cat << 'EOF' > /app/libmathops-1.2.0/mathops.h
#ifndef MATHOPS_H
#define MATHOPS_H
char* compute_fib(long long n, long long mod);
#endif
EOF

    cat << 'EOF' > /app/libmathops-1.2.0/mathops.c
#include <stdio.h>
#include <stdlib.h>
#include "mathops.h"

char* compute_fib(long long n, long long mod) {
    long long a = 0, b = 1, c;
    for (long long i = 0; i < n; i++) {
        c = (a + b) % mod;
        a = b;
        b = c;
    }
    char* res = malloc(64);
    sprintf(res, "%lld", a);
    return res;
}
EOF

    cat << 'EOF' > /app/libmathops-1.2.0/Makefile
CC=gcc
CFLAGS=-O3 -Wall
LDFLAGS=-shared

all: libmathops.so

libmathops.so: mathops.o
	$(CC) $(LDFLAGS) -o $@ $^

mathops.o: mathops.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o *.so
EOF

    # Create PR-104 files
    cat << 'EOF' > /app/pr-104/fibfast.c
#include <bash/config.h>
#include <bash/builtins.h>
#include <bash/shell.h>
#include <bash/builtins/common.h>
#include <stdio.h>
#include <stdlib.h>

extern char* compute_fib(long long n, long long mod);

int fibfast_builtin(WORD_LIST *list) {
    if (!list || !list->next) {
        builtin_usage();
        return EX_USAGE;
    }
    long long n = atoll(list->word->word);
    long long mod = atoll(list->next->word->word);

    char* res = compute_fib(n, mod);
    printf("%s\n", res);
    // Missing free(res);
    return EXECUTION_SUCCESS;
}

char *fibfast_doc[] = {
    "Compute fibonacci modulo.",
    "",
    "Usage: fibfast n mod",
    (char *)NULL
};

struct builtin fibfast_struct = {
    "fibfast",
    fibfast_builtin,
    BUILTIN_ENABLED,
    fibfast_doc,
    "fibfast n mod",
    0
};
EOF

    cat << 'EOF' > /app/pr-104/Makefile
CC=gcc
CFLAGS=-fPIC -I/usr/include/bash -I/usr/include/bash/include -I/usr/include/bash/builtins -I/app/libmathops-1.2.0
LDFLAGS=-shared -L/app/libmathops-1.2.0 -lmathops

all: fibfast.so

fibfast.so: fibfast.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f fibfast.so
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
