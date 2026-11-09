#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc patch
    pip3 install pytest

    mkdir -p /home/user/src /home/user/bin

    cat << 'EOF' > /home/user/versions.expr
MAJOR=4+8/2
MINOR=2**3-1
EOF

    cat << 'EOF' > /home/user/src/app.c
#include <stdio.h>
#include <stdlib.h>

#ifndef VERSION
#define VERSION "0.0"
#endif

int main() {
    int *arr = malloc(5 * sizeof(int));
    arr[0] = 1;
    printf("App Version: %s\n", VERSION);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/memory_leak_fix.patch
--- src/app.c
+++ src/app.c
@@ -8,5 +8,6 @@
 int main() {
     int *arr = malloc(5 * sizeof(int));
     arr[0] = 1;
+    free(arr);
     printf("App Version: %s\n", VERSION);
     return 0;
 }
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
