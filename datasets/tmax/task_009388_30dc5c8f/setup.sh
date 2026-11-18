#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/waf_util
    cd /home/user/waf_util

    cat << 'EOF' > match.s
.global match_traversal
.text
match_traversal:
    mov %rdi, %rax
loop:
    cmpb $0, (%rax)
    je not_found
    cmpb $46, (%rax)
    jne next
    cmpb $46, 1(%rax)
    jne next
    cmpb $47, 2(%rax)
    je found
next:
    inc %rax
    jmp loop
found:
    mov $1, %rax
    ret
not_found:
    mov $0, %rax
    ret
EOF
    tar -czf deps.tar.gz match.s
    rm match.s

    cat << 'EOF' > waf.c
#include <stdio.h>
#include <stdlib.h>

// Missing external function declaration

int main() {
    char *qs = getenv("QUERY_STRING");
    if (!qs) {
        printf("Status: 400 Bad Request\n\n");
        return 0;
    }

    if (match_traversal(qs)) {
        printf("Status: 403 Forbidden\n\n");
    } else {
        printf("Status: 200 OK\n\n")
    }
    return 0;
}
EOF

    cat << 'EOF' > Makefile
waf.out: waf.o match.o
    gcc -o waf.out waf.o match.o

waf.o: waf.c
    gcc -c waf.c

match.o: match.s
    gcc -c match.s

clean:
    rm -f *.o waf.out
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/waf_util
    chmod -R 777 /home/user
