#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc patch tar
    pip3 install pytest

    mkdir -p /home/user/waf_project/src /home/user/waf_project/include /home/user/waf_project/tests

    cat << 'EOF' > /home/user/waf_project/include/waf.h
#ifndef WAF_H
#define WAF_H

typedef struct {
    char *method;
    char *uri;
    char *header_name;
    char *header_value;
} HttpRequest;

int analyze_request(HttpRequest *req);

#endif
EOF

    cat << 'EOF' > /home/user/waf_project/src/parser.c
#include "waf.h"
#include <stdlib.h>
#include <string.h>

int analyze_request(HttpRequest *req) {
    if (strstr(req->header_value, "<script>")) return 1; // Blocked
    return 0; // Allowed
}
EOF

    cat << 'EOF' > /home/user/waf_project/tests/main.c
#include "waf.h"
#include <stdio.h>
#include <stdlib.h>

extern void setup_mock_request(HttpRequest *req);

int main() {
    HttpRequest req;
    setup_mock_request(&req);
    int result = analyze_request(&req);
    if (result == 1) {
        printf("Test passed: Request blocked.\n");
    } else {
        printf("Test failed: Request allowed.\n");
        return 1;
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/patch.diff
--- src/parser.c
+++ src/parser.c
@@ -4,6 +4,8 @@
 #include <string.h>

 int analyze_request(HttpRequest *req) {
+    char *temp_val = strdup(req->header_value);
     if (strstr(req->header_value, "<script>")) return 1; // Blocked
+    free(temp_val);
     return 0; // Allowed
 }
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
