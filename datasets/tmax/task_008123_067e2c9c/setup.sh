#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/waf_test_env/src

    cat << 'EOF' > /home/user/waf_test_env/src/main.c
// BUG: missing stdio.h and stdlib.h

void print_rules() {
    printf("Rule:init_req Cost:2\n");
    printf("Rule:parse_headers Cost:5\n");
    printf("Rule:check_sqli Cost:8\n");
    printf("Rule:check_xss Cost:4\n");
    printf("Rule:rate_limit Cost:3\n");
    printf("Rule:forward_req Cost:1\n");

    printf("Dep:parse_headers Requires:init_req\n");
    printf("Dep:check_sqli Requires:parse_headers\n");
    printf("Dep:check_xss Requires:parse_headers\n");
    printf("Dep:rate_limit Requires:init_req\n");
    printf("Dep:forward_req Requires:check_sqli\n");
    printf("Dep:forward_req Requires:check_xss\n");
    printf("Dep:forward_req Requires:rate_limit\n");
}

int main() {
    print_rules();
    return 0;
}
EOF

    cat << 'EOF' > /home/user/waf_test_env/Makefile
CC_COMP=gcc
CFLAGS=-I.

all: waf_analyzer

waf_analyzer: src/main.o
    $(CC) -o waf_analyzer src/main.o

src/main.o: src/main.c
    $(CC_COMP) -c src/main.c -o src/main.o
EOF

    sed -i 's/    /\t/g' /home/user/waf_test_env/Makefile
    sed -i 's/\t/    /g' /home/user/waf_test_env/Makefile

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
