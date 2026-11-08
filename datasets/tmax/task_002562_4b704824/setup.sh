#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make strace binutils gdb libc6-dev sudo
    pip3 install pytest

    mkdir -p /home/user/math_build

    cat << 'EOF' > /home/user/math_build/mathblob.c
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>

int calculate_magic(int a, int b) {
    if (b == 0) {
        // Force a system call trace to find the failure
        int fd = open("/home/user/math_build/fallback.dat", O_RDONLY);
        if (fd < 0) {
            // Intentionally crash if fallback doesn't exist and b is 0
            abort();
        }
        close(fd);
        return 0;
    }
    return (a * a) / b;
}
EOF

    gcc -c /home/user/math_build/mathblob.c -o /home/user/math_build/mathblob.o
    rm /home/user/math_build/mathblob.c

    cat << 'EOF' > /home/user/math_build/generator.c
#include <stdio.h>

extern int calculate_magic(int a, int b);

int main() {
    FILE *f = fopen("table.h", "w");
    if (!f) return 1;
    fprintf(f, "int magic_table[10] = {\n");
    for(int i = 0; i < 10; i++) {
        // BUG: passes i as second argument, triggering divide-by-zero/abort when i=0
        int val = calculate_magic(i, i);
        fprintf(f, "%d,\n", val);
    }
    fprintf(f, "};\n");
    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/math_build/main.c
#include <stdio.h>
#include "table.h"

int main() {
    int sum = 0;
    for(int i = 0; i < 10; i++) {
        sum += magic_table[i];
    }
    printf("%d\n", sum);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/math_build/Makefile
all: math_app

generator: generator.c mathblob.o
	gcc -o generator generator.c mathblob.o

table.h: generator
	./generator

math_app: main.c table.h
	gcc -o math_app main.c

clean:
	rm -f generator table.h math_app
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/math_build
    chmod -R 777 /home/user
