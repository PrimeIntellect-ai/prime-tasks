#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential patch binutils
    pip3 install pytest

    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/src/main.c
#include <stdio.h>
#include <math.h>

int main() {
    printf("Starting utility...\n");
    double val = cos(1.0);
    printf("Cos: %f\n", val);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/src/Makefile
all:
	gcc main.c -lm -o util_full

EOF

    cat << 'EOF' > /home/user/pr.patch
--- main.c
+++ main.c
@@ -1,9 +1,15 @@
 #include <stdio.h>
+#ifndef MINIMAL_BUILD
 #include <math.h>
+#endif

 int main() {
     printf("Starting utility...\n");
+#ifndef MINIMAL_BUILD
     double val = cos(1.0);
     printf("Cos: %f\n", val);
+#else
+    printf("Minimal mode active.\n");
+#endif
     return 0;
 }
--- Makefile
+++ Makefile
@@ -1,3 +1,5 @@
 all:
 	gcc main.c -lm -o util_full

+target_minimal:
+	gcc main.c -lm -o util_min
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
