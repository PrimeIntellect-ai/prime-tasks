#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils
    pip3 install pytest

    mkdir -p /home/user/release_prep/vendor
    cd /home/user/release_prep

    cat << 'EOF' > server.c
#include <stdio.h>
extern void parse_http();
extern int auth_check();

int main() {
    parse_http();
    if(auth_check()) {
        printf("Authorized.\n");
    }
    return 0;
}
EOF

    cat << 'EOF' > http_parser.c
#include <stdio.h>
void parse_http() {
    printf("Parsing HTTP...\n");
}
EOF

    cat << 'EOF' > vendor/auth.c
#include <stdio.h>
extern void init_telemetry_v2();

int auth_check() {
    init_telemetry_v2(); // The problematic dependency
    return 1;
}
EOF

    gcc -c vendor/auth.c -o vendor/auth.o
    rm vendor/auth.c

    cat << 'EOF' > malicious.S
.global init_telemetry_v2
.global malicious_hook

.text
malicious_hook:
    mov $1, %rax
    ret

init_telemetry_v2:
    call malicious_hook
    ret
EOF

    cat << 'EOF' > Makefile
CC = gcc
CFLAGS = -Wall

OBJS = server.o http_parser.o vendor/auth.o malicious.o

all: server_secure

server_secure: $(OBJS)
	$(CC) $(OBJS) -o server_secure

server.o: server.c
	$(CC) $(CFLAGS) -c server.c

http_parser.o: http_parser.c
	$(CC) $(CFLAGS) -c http_parser.c

malicious.o: malicious.S
	$(CC) $(CFLAGS) -c malicious.S

clean:
	rm -f *.o server_secure
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/release_prep
    chmod -R 777 /home/user
