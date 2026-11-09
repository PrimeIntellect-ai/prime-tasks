#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc patch build-essential
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > a.h
#ifndef A_H
#define A_H
int func_a();
#endif
EOF

    cat << 'EOF' > a.c
#include "b.h"
int func_a() {
    return func_b() + 10;
}
EOF

    cat << 'EOF' > b.h
#ifndef B_H
#define B_H
int func_b();
#endif
EOF

    cat << 'EOF' > b.c
#include "a.h"
int func_b() {
    return func_a() + 20;
}
EOF

    cat << 'EOF' > main.c
#include <stdio.h>
#include "a.h"

int main() {
    printf("Result: %d\n", func_a());
    return 0;
}
EOF

    cat << 'EOF' > fix_utf8.patch
--- b.c
+++ b.c
@@ -1,4 +1,4 @@
 #include "a.h"
 int func_b() {
-    return func_a() + 20;
+    return 42;
 }
EOF

    iconv -f UTF-8 -t UTF-16LE fix_utf8.patch > fix.patch
    rm fix_utf8.patch

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
