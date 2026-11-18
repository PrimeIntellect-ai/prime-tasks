#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv gcc make patch curl

pip3 install pytest

mkdir -p /home/user/workspace

cat << 'EOF' > /home/user/workspace/waf.c
#include <string.h>

int validate_request(const char* payload) {
    if (payload == NULL) return 0;
    if (strstr(payload, "DROP TABLE") != NULL) {
        return 0;
    }
    return 1;
}
EOF

cat << 'EOF' > /home/user/workspace/waf_security.patch
--- waf.c
+++ waf.c
@@ -5,5 +5,8 @@
     if (strstr(payload, "DROP TABLE") != NULL) {
         return 0;
     }
+    if (strstr(payload, "<script>") != NULL) {
+        return 0;
+    }
     return 1;
 }
EOF

cat << 'EOF' > /home/user/workspace/Makefile
all:
	gcc -o waf waf.c
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
