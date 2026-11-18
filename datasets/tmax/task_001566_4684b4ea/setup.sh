#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user /app

    cat << 'EOF' > /app/log_distance.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int levenshtein(const char *s, int ls, const char *t, int lt) {
    int a, b, c;
    if (!ls) return lt;
    if (!lt) return ls;
    if (s[ls-1] == t[lt-1]) return levenshtein(s, ls-1, t, lt-1);
    a = levenshtein(s, ls-1, t, lt-1);
    b = levenshtein(s, ls, t, lt-1);
    c = levenshtein(s, ls-1, t, lt);
    if (a > b) a = b;
    if (a > c) a = c;
    return a + 1;
}

int main(int argc, char **argv) {
    if(argc != 3) return 1;
    int dist = levenshtein(argv[1], strlen(argv[1]), argv[2], strlen(argv[2]));
    printf("%.2f\n", (float)dist / strlen(argv[1]));
    return 0;
}
EOF
    gcc -O2 -s /app/log_distance.c -o /app/log_distance
    rm /app/log_distance.c

    cat << 'EOF' > /home/user/logs.csv
raw_timestamp,user_ip,action,details
1696420800,10.0.0.1,login,successful login
10/04/2023 12:05:00,192.168.1.5,exploit,root shell attempt
1696421400,172.16.0.4,exploit,root shell attempt failed
10/04/2023 12:15:00,8.8.8.8,ping,icmp echo
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
