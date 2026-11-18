#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/rate_limiter

    cat << 'EOF' > /home/user/rate_limiter/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern unsigned int string_hash(const char *str);

typedef struct {
    char ip[20];
    int last_time;
    int count;
} Record;

Record table[1024];

int main(int argc, char **argv) {
    if(argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char ip[20];
    int time;
    while(fscanf(f, "%19s %d", ip, &time) == 2) {
        unsigned int h = string_hash(ip) % 1024;
        if(strcmp(table[h].ip, ip) != 0) {
            strcpy(table[h].ip, ip);
            table[h].last_time = time;
            table[h].count = 1;
            printf("ALLOW %s %d\n", ip, time);
        } else {
            if(time - table[h].last_time < 5) {
                table[h].count++;
                if(table[h].count <= 2) {
                    printf("ALLOW %s %d\n", ip, time);
                } else {
                    printf("DENY %s %d\n", ip, time);
                }
            } else {
                table[h].last_time = time;
                table[h].count = 1;
                printf("ALLOW %s %d\n", ip, time);
            }
        }
    }
    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/rate_limiter/hash.s
.global string_hash
.text
string_hash:
    mov $5381, %eax
.loop:
    movzbq (%rdi), %rcx
    test %rcx, %rcx
    jz .done
    imul $33, %eax, %eax
    add %ecx, %eax
    inc %rdi
    jmp .loop
.done:
    ret
EOF

    cat << 'EOF' > /home/user/rate_limiter/Makefile
all: rate_limit_checker

hash.o: hash.s
	gcc -c hash.s -o hash.o

main.o: main.c
	gcc -c main.c -o main.o

rate_limit_checker: main.o hash.o
	gcc main.o -o rate_limit_checker
EOF

    cat << 'EOF' > /home/user/rate_limiter/requests.log
192.168.1.1 10
192.168.1.1 12
192.168.1.1 13
10.0.0.1 14
192.168.1.1 20
10.0.0.1 15
10.0.0.1 16
EOF

    chmod -R 777 /home/user
