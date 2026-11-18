#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make sqlite3
    pip3 install pytest

    # Create fast-calc directory and files
    mkdir -p /app/fast-calc-2.1.0

    cat << 'EOF' > /app/fast-calc-2.1.0/fast_calc.c
#include <math.h>
double calculate(double a, double b) {
    return sin(a) + cos(b);
}
EOF

    cat << 'EOF' > /app/fast-calc-2.1.0/fast_math.S
.global fast_add
.type fast_add, @function
fast_add:
    add %rdi, %rsi
    mov %rsi, %rax
    ret
EOF

    cat << 'EOF' > /app/fast-calc-2.1.0/Makefile
CC=clang-9
CFLAGS=-Wall -fPIC -m32
LDFLAGS=-shared

all: libfastcalc.so

libfastcalc.so: fast_calc.o fast_math.o
	$(CC) $(LDFLAGS) -o $@ $^

fast_calc.o: fast_calc.c
	$(CC) $(CFLAGS) -c $< -o $@

fast_math.o: fast_math.S
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o *.so
EOF

    # Create user and home directory
    useradd -m -s /bin/bash user || true

    # Create sqlite database
    sqlite3 /home/user/math_data.db << 'EOF'
CREATE TABLE equations_v1 (id INTEGER PRIMARY KEY, expression TEXT);
INSERT INTO equations_v1 (expression) VALUES ('3 + (4 * 2)');
INSERT INTO equations_v1 (expression) VALUES ('(1+(2+(3+(4+(5+(6))))))');
INSERT INTO equations_v1 (expression) VALUES ('10 / 0');
INSERT INTO equations_v1 (expression) VALUES ('5 % 2');
INSERT INTO equations_v1 (expression) VALUES ('100 / 2.5');
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
