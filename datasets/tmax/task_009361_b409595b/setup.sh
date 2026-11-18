#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make patch
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/repo
cd /home/user/repo

# Create original Makefile
cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-Wall -Wextra

ws_vm: main.c http_parser.c vm.c
	$(CC) $(CFLAGS) -o ws_vm main.c http_parser.c vm.c

clean:
	rm -f ws_vm
EOF

# Create original main.c
cat << 'EOF' > main.c
#include <stdio.h>
#include <stdint.h>
#include <string.h>

extern void parse_route(const char* req);
extern int run_vm(const uint8_t* code, int len);

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    if (strcmp(argv[1], "route") == 0 && argc == 3) {
        parse_route(argv[2]);
        printf("Route parsed.\n");
    } else if (strcmp(argv[1], "vm") == 0 && argc == 3) {
        uint8_t code[256];
        int len = 0;
        char* hex = argv[2];
        while (*hex && *(hex+1)) {
            sscanf(hex, "%2hhx", &code[len++]);
            hex += 2;
        }
        int res = run_vm(code, len);
        printf("VM Result: %d\n", res);
    }
    return 0;
}
EOF

# Create original http_parser.c
cat << 'EOF' > http_parser.c
#include <stdio.h>
#include <string.h>

void parse_route(const char* req) {
    // Simple mock logic
    printf("Parsing: %s\n", req);
}
EOF

# Create original vm.c
cat << 'EOF' > vm.c
#include <stdio.h>
#include <stdint.h>

#define OP_HALT 0x00
#define OP_INC  0x01

int run_vm(const uint8_t* code, int len) {
    int pc = 0;
    int acc = 0;
    while (pc < len) {
        switch (code[pc]) {
            case OP_HALT:
                return acc;
            case OP_INC:
                acc++;
                pc++;
                break;
            default:
                return -2; // Invalid instruction
        }
    }
    return acc;
}
EOF

cd /home/user

# Create the PR patch
cat << 'EOF' > pr.patch
diff --git a/Makefile b/Makefile
index abc..def 100644
--- a/Makefile
+++ b/Makefile
@@ -2,6 +2,7 @@ CC=gcc
 CFLAGS=-Wall -Wextra

 ws_vm: main.c http_parser.c vm.c
-	$(CC) $(CFLAGS) -o ws_vm main.c http_parser.c vm.c
+       # Added debug flags but accidentally used spaces instead of tabs, breaking Make
+       $(CC) $(CFLAGS) -g -o ws_vm main.c http_parser.c vm.c

 clean:
diff --git a/http_parser.c b/http_parser.c
index abc..def 100644
--- a/http_parser.c
+++ b/http_parser.c
@@ -3,5 +3,7 @@

 void parse_route(const char* req) {
-    // Simple mock logic
-    printf("Parsing: %s\n", req);
+    char route[16];
+    // Extract route logic
+    strcpy(route, req);
+    printf("Routed to: %s\n", route);
 }
diff --git a/vm.c b/vm.c
index abc..def 100644
--- a/vm.c
+++ b/vm.c
@@ -5,6 +5,7 @@
 #define OP_HALT 0x00
 #define OP_INC  0x01
+#define OP_JMP  0x02

 int run_vm(const uint8_t* code, int len) {
     int pc = 0;
@@ -17,6 +18,10 @@ int run_vm(const uint8_t* code, int len) {
                 acc++;
                 pc++;
                 break;
+            case OP_JMP:
+                // Read offset and jump
+                pc += (int8_t)code[pc+1];
+                break;
             default:
                 return -2; // Invalid instruction
EOF

# Create the test script
cat << 'EOF' > /home/user/run_tests.sh
#!/bin/bash
cd /home/user/repo

if [ ! -f "ws_vm" ]; then
    echo "FAILED: ws_vm binary not found."
    exit 1
fi

# Test 1: Buffer overflow test
# A long string should not cause a segfault if correctly truncated/handled safely.
./ws_vm route "this_is_a_very_long_route_string_that_will_overflow_the_sixteen_byte_buffer" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "FAILED: Buffer overflow crash detected."
    exit 1
fi

# Test 2: VM Bounds Check Test
# 02 is OP_JMP, 7f is large positive jump. Should return -1.
RES=$(./ws_vm vm 027f 2>/dev/null)
if [[ ! "$RES" == *"VM Result: -1"* ]]; then
    echo "FAILED: VM did not return -1 on out-of-bounds jump."
    exit 1
fi

# Test 3: Valid VM operations
# 01 (INC), 02 01 (JMP +1), 01 (INC skipped), 01 (INC executed), 00 (HALT). Expected result: 2.
RES2=$(./ws_vm vm 010201010100 2>/dev/null)
if [[ ! "$RES2" == *"VM Result: 2"* ]]; then
    echo "FAILED: Valid VM execution failed. $RES2"
    exit 1
fi

echo "ALL_PASSED" > /home/user/final_result.txt
echo "Success!"
EOF
chmod +x /home/user/run_tests.sh

chown -R user:user /home/user/repo /home/user/pr.patch /home/user/run_tests.sh
chmod -R 777 /home/user
