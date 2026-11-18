#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc patch
    pip3 install pytest

    mkdir -p /home/user/app/src /home/user/app/patches /home/user/app/build /home/user/app/tests

    cat << 'EOF' > /home/user/app/src/libauth.c
#include <stdio.h>
#include <string.h>

int verify_token(const char* token) {
    char buffer[16];
    // Vulnerable string copy
    strcpy(buffer, token);
    if (strcmp(buffer, "ADMIN_TOKEN") == 0) {
        return 1;
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/patches/CVE-2024-9999.patch
--- libauth.c	2024-01-01 00:00:00.000000000 +0000
+++ libauth.c	2024-01-01 00:00:01.000000000 +0000
@@ -4,7 +4,7 @@
 int verify_token(const char* token) {
     char buffer[16];
-    // Vulnerable string copy
-    strcpy(buffer, token);
+    // Safe string copy
+    strncpy(buffer, token, 15);
+    buffer[15] = '\0';
     if (strcmp(buffer, "ADMIN_TOKEN") == 0) {
         return 1;
     }
EOF

    cat << 'EOF' > /home/user/app/manifest.json
{
    "components": {
        "web_framework": {"version": "2.1.0"},
        "libauth": {"version": "1.0.0"}
    }
}
EOF

    cat << 'EOF' > /home/user/app/tests/e2e_test.py
#!/usr/bin/env python3
import ctypes
import os
import sys

def run_tests():
    lib_path = "/home/user/app/build/libauth.so"
    if not os.path.exists(lib_path):
        print("Library not found!")
        sys.exit(1)

    try:
        auth_lib = ctypes.CDLL(lib_path)
    except Exception as e:
        print(f"Failed to load library: {e}")
        sys.exit(1)

    # Test normal auth
    res = auth_lib.verify_token(b"ADMIN_TOKEN")
    if res != 1:
        print("Valid token failed!")
        sys.exit(1)

    # Test buffer overflow payload
    payload = b"A" * 50
    try:
        res = auth_lib.verify_token(payload)
        # If it didn't segfault, the patch worked
        with open("/home/user/app/test_results.log", "w") as f:
            f.write("E2E SEC TEST: PASS\n")
        print("Tests passed safely.")
    except Exception as e:
        print("Segmentation fault or error! Patch failed.")
        sys.exit(1)

if __name__ == "__main__":
    run_tests()
EOF

    chmod +x /home/user/app/tests/e2e_test.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
