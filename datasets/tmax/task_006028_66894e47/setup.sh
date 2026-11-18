#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc git binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/system_logs
    mkdir -p /home/user/repo
    mkdir -p /home/user/legacy

    # 1. Generate Logs
    cat << 'EOF' > /home/user/system_logs/api_gateway.log
[10:00:01] REQ-1001 : Dispatching x=10 y=20
[10:00:05] REQ-1002 : Dispatching x=500 y=300
[10:00:12] REQ-1003 : Dispatching x=85000 y=92000
[10:00:18] REQ-1004 : Dispatching x=90000 y=90000
EOF

    cat << 'EOF' > /home/user/system_logs/calc_service.log
[10:00:02] REQ-1001 : Result is 200
[10:00:06] REQ-1002 : Result is 150000
[10:00:13] REQ-1003 : Result is -769307904
[10:00:19] REQ-1004 : Result is -489886302
EOF

    # 2. Generate Oracle Binary
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char** argv) {
    long long x = atoll(argv[1]);
    long long y = atoll(argv[2]);
    long long res = (x * y) ^ 0xCAFEBABE;
    printf("%lld\n", res);
    return 0;
}
EOF
    gcc -O2 /tmp/oracle.c -o /home/user/legacy/oracle
    strip /home/user/legacy/oracle

    # 3. Setup Git Repo
    cd /home/user/repo
    git init
    git config --local user.email "user@example.com"
    git config --local user.name "User"

    cat << 'EOF' > Makefile
calc: calc.c
	gcc -fwrapv -O0 -g calc.c -o calc
EOF

    cat << 'EOF' > calc.c
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char** argv) {
    long long x = atoll(argv[1]);
    long long y = atoll(argv[2]);
    long long res = x * y;
    printf("%lld\n", res);
    return 0;
}
EOF
    git add Makefile calc.c
    git commit -m "Initial commit"

    # Good commits
    for i in {1..4}; do
        echo "// comment $i" >> calc.c
        git commit -am "Dummy commit $i"
    done

    # Bad commit: introduce overflow
    cat << 'EOF' > calc.c
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char** argv) {
    long long x = atoll(argv[1]);
    long long y = atoll(argv[2]);
    int mult = x * y; // overflow
    long long res = mult;
    printf("%lld\n", res);
    return 0;
}
EOF
    git commit -am "Refactor calculation logic"
    BAD_COMMIT=$(git rev-parse HEAD)
    echo "$BAD_COMMIT" > /tmp/bad_commit_hash.txt

    # More dummy commits
    for i in {5..8}; do
        echo "// comment $i" >> calc.c
        git commit -am "Dummy commit $i"
    done

    chown -R user:user /home/user
    chmod -R 777 /home/user
