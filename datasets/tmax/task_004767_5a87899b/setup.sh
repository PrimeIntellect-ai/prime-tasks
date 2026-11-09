#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc patch
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/workspace/payloads

    cat << 'EOF' > /home/user/workspace/libseccheck.c
#include <string.h>
int check_payload(const char* payload) {
    if (strstr(payload, "<script>") != NULL) return 0;
    return 1;
}
EOF

    cat << 'EOF' > /home/user/workspace/security_fix.patch
--- libseccheck.c
+++ libseccheck.c
@@ -1,5 +1,6 @@
 #include <string.h>
-int check_payload(const char* payload) {
+int check_payload(const char* payload, int length) {
+    if (length > 100) return 0;
     if (strstr(payload, "<script>") != NULL) return 0;
     return 1;
 }
EOF

    cat << 'EOF' > /home/user/workspace/payloads/p1.json
{"id": "config_alpha", "data": "Standard configuration data without any malicious content."}
EOF

    cat << 'EOF' > /home/user/workspace/payloads/p2.json
{"id": "config_beta", "data": "Includes some inline JS <script>alert(1)</script> for testing."}
EOF

    cat << 'EOF' > /home/user/workspace/payloads/p3.json
{"id": "config_gamma", "data": "This is a very long configuration string that is specifically designed to exceed the one hundred character limit that is enforced by the newly patched security library."}
EOF

    cat << 'EOF' > /home/user/workspace/payloads/p4.json
{"id": "config_delta", "data": "Short, safe, and sweet."}
EOF

    chmod -R 777 /home/user
