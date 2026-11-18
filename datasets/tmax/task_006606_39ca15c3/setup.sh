#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make strace patch binutils libc6-dev
    pip3 install pytest

    mkdir -p /home/user/incident-104
    cd /home/user/incident-104

    # 1. Create the C source code
    cat << 'EOF' > processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main() {
    FILE *f = fopen("/home/user/incident-104/.secret_token", "r");
    if (!f) {
        perror("Init error: configuration missing");
        return 1;
    }
    char token[256];
    if (!fgets(token, sizeof(token), f)) {
        fclose(f);
        return 1;
    }
    fclose(f);

    // Trim newline if present
    token[strcspn(token, "\n")] = 0;

    if (strncmp(token, "TOKEN_8f9a2b4c6d", 16) != 0) {
        printf("Invalid token.\n");
        return 1;
    }

    double val = 144.0;
    double res = val / 2.0;
    printf("SUCCESS_HASH_%d\n", (int)res);
    return 0;
}
EOF

    # 2. Compile the initial binary
    gcc processor.c -o data_processor

    # 3. Create the fake core dump with the token
    dd if=/dev/urandom of=core bs=1024 count=10 2>/dev/null
    echo "MEMORY_CORRUPTION_PREVENTION_STRING_TOKEN_8f9a2b4c6d_MORE_GARBAGE_DATA" >> core
    dd if=/dev/urandom of=core bs=1024 count=10 oflag=append conv=notrunc 2>/dev/null

    # 4. Create the patch file
    cat << 'EOF' > patch.diff
--- processor.c
+++ processor.c
@@ -25,3 +25,3 @@
     double val = 144.0;
-    double res = val / 2.0;
+    double res = sqrt(val);
     printf("SUCCESS_HASH_%d\n", (int)res);
EOF

    # 5. Create the initial Makefile
    cat << 'EOF' > Makefile
all: data_processor

data_processor: processor.c
	gcc processor.c -o data_processor

clean:
	rm -f data_processor
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/incident-104
    chmod -R 777 /home/user
