#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/log_merger
    mkdir -p /home/user/logs
    mkdir -p /app

    cat << 'EOF' > /home/user/log_merger/main.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char** argv) {
    if (argc < 3) return 1;
    double d = sqrt(4.0);
    FILE *f1 = fopen(argv[1], "r");
    FILE *f2 = fopen(argv[2], "r");
    char buf[256];
    if (f1) { while(fgets(buf, 256, f1)) printf("%s", buf); fclose(f1); }
    if (f2) { while(fgets(buf, 256, f2)) printf("%s", buf); fclose(f2); }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/log_merger/Makefile
log_merger: main.o
	gcc -o log_merger main.o
main.o: main.c
	gcc -c main.c
EOF

    echo "node1 log entry 1" > /home/user/logs/node1.log
    echo "node1 log entry 2" >> /home/user/logs/node1.log
    echo "node2 log entry 1" > /home/user/logs/node2.log
    echo "node2 log entry 2" >> /home/user/logs/node2.log

    cat << 'EOF' > /tmp/waf.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

void urldecode(char *dst, const char *src) {
    char a, b;
    while (*src) {
        if ((*src == '%') &&
            ((a = src[1]) && (b = src[2])) &&
            (isxdigit(a) && isxdigit(b))) {
            if (a >= 'a') a -= 'a'-'A';
            if (a >= 'A') a -= ('A' - 10);
            else a -= '0';
            if (b >= 'a') b -= 'a'-'A';
            if (b >= 'A') b -= ('A' - 10);
            else b -= '0';
            *dst++ = 16*a+b;
            src+=3;
        } else {
            *dst++ = *src++;
        }
    }
    *dst++ = '\0';
}

void normalize(char *str) {
    char *p = str;
    char *q = str;
    while (*p) {
        *q++ = *p;
        if (*p == '/') {
            while (*(p+1) == '/') p++;
        }
        p++;
    }
    *q = '\0';

    while ((p = strstr(str, "/./")) != NULL) {
        memmove(p, p + 2, strlen(p + 2) + 1);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) return 0;
    char decoded[4096];
    urldecode(decoded, argv[1]);
    normalize(decoded);

    if (strstr(decoded, "../") ||
        strstr(decoded, ".env") ||
        strstr(decoded, ".php") ||
        strstr(decoded, "<script>") ||
        strstr(decoded, "admin/")) {
        printf("BLOCK\n");
        return 1;
    }
    printf("ALLOW\n");
    return 0;
}
EOF

    gcc -o /app/waf_evaluator_stripped /tmp/waf.c
    strip /app/waf_evaluator_stripped
    rm /tmp/waf.c

    chown -R user:user /home/user
    chmod -R 777 /home/user
