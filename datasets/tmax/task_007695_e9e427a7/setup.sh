#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make patch
    pip3 install pytest

    mkdir -p /home/user/vector_api
    cd /home/user/vector_api

    cat << 'EOF' > vector_math.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

long long gcd(long long a, long long b) {
    if (a < 0) a = -a;
    while (b) {
        a %= b;
        long long temp = a;
        a = b;
        b = temp;
    }
    return a;
}

char* dot_product(const char* v1, const char* v2) {
    int sz1, sz2;
    sscanf(v1, "[%d]", &sz1);
    sscanf(v2, "[%d]", &sz2);

    if (sz1 != sz2) return strdup("ERROR");

    const char *p1 = strchr(v1, ']'); if(p1) p1++;
    const char *p2 = strchr(v2, ']'); if(p2) p2++;

    long long total_n = 0;
    long long total_d = 1;

    for (int i = 0; i < sz1; i++) {
        unsigned int n1_u, n2_u;
        unsigned int d1, d2;

        // Advance to next token
        while(*p1 == ' ') p1++;
        while(*p2 == ' ') p2++;

        // BUG: parses as unsigned
        sscanf(p1, "%u/%u", &n1_u, &d1);
        sscanf(p2, "%u/%u", &n2_u, &d2);

        long long n1 = (long long)n1_u;
        long long n2 = (long long)n2_u;

        long long prod_n = n1 * n2;
        long long prod_d = (long long)d1 * d2;

        long long new_n = total_n * prod_d + prod_n * total_d;
        long long new_d = total_d * prod_d;

        long long g = gcd(new_n, new_d);
        total_n = new_n / g;
        total_d = new_d / g;

        p1 = strchr(p1, ' ');
        p2 = strchr(p2, ' ');
    }

    char* result = malloc(64);
    if (total_d < 0) {
        total_n = -total_n;
        total_d = -total_d;
    }
    sprintf(result, "%lld/%lld", total_n, total_d);
    return result;
}
EOF

    cat << 'EOF' > negative_fix.patch
--- vector_math.c
+++ vector_math.c
@@ -27,15 +27,15 @@
     long long total_d = 1;

     for (int i = 0; i < sz1; i++) {
-        unsigned int n1_u, n2_u;
+        int n1_u, n2_u;
         unsigned int d1, d2;

         // Advance to next token
         while(*p1 == ' ') p1++;
         while(*p2 == ' ') p2++;

-        // BUG: parses as unsigned
-        sscanf(p1, "%u/%u", &n1_u, &d1);
-        sscanf(p2, "%u/%u", &n2_u, &d2);
+        // FIX: parses as signed int
+        sscanf(p1, "%d/%u", &n1_u, &d1);
+        sscanf(p2, "%d/%u", &n2_u, &d2);

         long long n1 = (long long)n1_u;
EOF

    cat << 'EOF' > Makefile
libvector.so: vector_math.c
	gcc -shared -fPIC -o libvector.so vector_math.c
EOF

    cat << 'EOF' > test_cases.json
{
  "case1": {"v1": "[3] 1/2 -3/4 5/1", "v2": "[3] 2/1 1/3 -1/5"},
  "case2": {"v1": "[2] -1/1 -1/1", "v2": "[2] -1/1 -1/1"},
  "case3": {"v1": "[4] 1/3 2/3 3/3 -4/3", "v2": "[4] -1/2 1/4 -1/8 -1/16"}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
