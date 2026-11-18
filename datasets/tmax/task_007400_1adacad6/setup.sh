#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk make gcc patch
    pip3 install pytest

    mkdir -p /home/user/qa_env

    cat << 'EOF' > /home/user/qa_env/vectors.json
{
  "vector_x": [15, 22, 9, 31],
  "vector_y": [4, 11, 25, 6]
}
EOF

    cat << 'EOF' > /home/user/qa_env/main.c
#include <stdio.h>
#include "config.h"

int main() {
    printf("Test Output Verification: %d\n", DOT_PRODUCT);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/qa_env/Makefile
math_eval: main.o
	gcc main.o -o math_eval
main.o: main.c
	gcc -c main.c -I/nonexistent/path
EOF

    cat << 'EOF' > /home/user/qa_env/fix_build.patch
--- Makefile
+++ Makefile
@@ -3,2 +3,2 @@
-main.o: main.c
-	gcc -c main.c -I/nonexistent/path
+main.o: main.c config.h
+	gcc -c main.c -I.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
