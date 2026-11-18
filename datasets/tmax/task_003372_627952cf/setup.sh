#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /app/vendored/uroute-0.5.1
    mkdir -p /app/corpora/clean_requests
    mkdir -p /app/corpora/evil_requests

    cat << 'EOF' > /app/vendored/uroute-0.5.1/main.c
#include <stdio.h>
#include <string.h>
extern int parse_route(const char* path);
int main(int argc, char** argv) {
    if (argc < 2) return 1;
    return parse_route(argv[1]);
}
EOF

    cat << 'EOF' > /app/vendored/uroute-0.5.1/route_tree.c
int validate_node(const char* node) {
    return 0; // stub
}
EOF

    cat << 'EOF' > /app/vendored/uroute-0.5.1/parser.c
#include <string.h>
int parse_route(const char* path) {
    if (strcmp(path, "/api/v1/users") == 0) return 0;
    if (strcmp(path, "/api/v1/posts") == 0) return 0;
    return 1;
}
EOF

    cat << 'EOF' > /app/vendored/uroute-0.5.1/Makefile
CC = gcc
CFLAGS = -Wall
OBJS = main.o route_tree.o

uroute_cli: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS)

EOF

    echo '%.o: %.c' >> /app/vendored/uroute-0.5.1/Makefile
    echo '	$(CC) $(CFLAGS) -c $< -o $@' >> /app/vendored/uroute-0.5.1/Makefile
    echo '' >> /app/vendored/uroute-0.5.1/Makefile
    echo 'clean:' >> /app/vendored/uroute-0.5.1/Makefile
    echo '	rm -f *.o uroute_cli' >> /app/vendored/uroute-0.5.1/Makefile

    echo "http://localhost/api/v1/users?chk=56&ops=010A010502" > /app/corpora/clean_requests/req1.txt
    echo "http://localhost/api/v1/posts?chk=51&ops=0105010A03" > /app/corpora/clean_requests/req2.txt

    echo "http://localhost/api/v1/users?chk=00&ops=010A010502" > /app/corpora/evil_requests/req1.txt
    echo "http://localhost/api/v1/users?chk=56&ops=0164010202" > /app/corpora/evil_requests/req2.txt
    echo "http://localhost/api/v1/users?chk=56&ops=02" > /app/corpora/evil_requests/req3.txt
    echo "http://localhost/api/v1/admin?chk=5A&ops=010A010502" > /app/corpora/evil_requests/req4.txt

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
