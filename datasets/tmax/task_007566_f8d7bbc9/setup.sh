#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make patch
    pip3 install pytest

    mkdir -p /home/user/project/tests

    cat << 'EOF' > /home/user/project/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define STATE_TARGET 0
#define STATE_DEPS 1

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    int state = STATE_TARGET;
    char target[256] = {0};
    char deps[512] = {0};
    int t_idx = 0, d_idx = 0;
    int c;

    while ((c = fgetc(f)) != EOF) {
        if (isspace(c)) {
            if (state == STATE_DEPS && d_idx > 0 && deps[d_idx-1] != ' ') {
                deps[d_idx++] = ' ';
            }
            continue;
        }

        if (state == STATE_TARGET) {
            if (c == ':') {
                target[t_idx] = '\0';
                state = STATE_DEPS;
            } else {
                target[t_idx++] = c;
            }
        } else if (state == STATE_DEPS) {
            if (c == ';') {
                if (d_idx > 0 && deps[d_idx-1] == ' ') d_idx--;
                deps[d_idx] = '\0';
                printf("Target: %s, Limit: 0, Deps: %s\n", target, deps);

                // Reset
                t_idx = 0; d_idx = 0;
                memset(target, 0, sizeof(target));
                memset(deps, 0, sizeof(deps));
                state = STATE_TARGET;
            } else {
                deps[d_idx++] = c;
            }
        }
    }
    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/Makefile
parser: parser.c
	gcc -Wall -Wextra -o parser parser.c
clean:
	rm -f parser
EOF

    cat << 'EOF' > /home/user/pr_123.patch
--- parser.c
+++ parser_new.c
@@ -5,17 +5,21 @@

 #define STATE_TARGET 0
+#define STATE_LIMIT 1
+#define STATE_EXPECT_COLON 2
-#define STATE_DEPS 1
+#define STATE_DEPS 3

 int main(int argc, char *argv[]) {
     if (argc < 2) return 1;
     FILE *f = fopen(argv[1], "r");
     if (!f) return 1;

     int state = STATE_TARGET;
     char target[256] = {0};
+    char limit_str[32] = {0};
     char deps[512] = {0};
-    int t_idx = 0, d_idx = 0;
+    int t_idx = 0, l_idx = 0, d_idx = 0;
+    int limit_val = 0;
     int c;

     while ((c = fgetc(f)) != EOF) {
@@ -27,8 +31,19 @@

         if (state == STATE_TARGET) {
-            if (c == ':') {
+            if (c == '(') {
+                // BUG: PR author forgot target[t_idx] = '\0'; here
+                state = STATE_LIMIT;
+            } else if (c == ':') {
                 target[t_idx] = '\0';
                 state = STATE_DEPS;
             } else {
                 target[t_idx++] = c;
             }
+        } else if (state == STATE_LIMIT) {
+            if (c == ')') {
+                limit_str[l_idx] = '\0';
+                limit_val = atoi(limit_str);
+                state = STATE_EXPECT_COLON;
+            } else {
+                limit_str[l_idx++] = c;
+            }
+        } else if (state == STATE_EXPECT_COLON) {
+            if (c == ':') {
+                state = STATE_DEPS;
+            }
         } else if (state == STATE_DEPS) {
             if (c == ';') {
@@ -37,10 +52,11 @@
                 deps[d_idx] = '\0';
-                printf("Target: %s, Limit: 0, Deps: %s\n", target, deps);
+                printf("Target: %s, Limit: %d, Deps: %s\n", target, limit_val, deps);

                 // Reset
-                t_idx = 0; d_idx = 0;
+                t_idx = 0; l_idx = 0; d_idx = 0; limit_val = 0;
                 memset(target, 0, sizeof(target));
+                memset(limit_str, 0, sizeof(limit_str));
                 memset(deps, 0, sizeof(deps));
                 state = STATE_TARGET;
             } else {
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
