#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make patch bash coreutils
    pip3 install pytest

    mkdir -p /home/user/waf-project/lib
    cd /home/user/waf-project

    cat << 'EOF' > deps.txt
waf: parser crypto
parser: log
crypto: log
log:
EOF

    cat << 'EOF' > waf_engine.c
#include <stdio.h>
void insecure_func() {
    printf("Vulnerable\n");
}
int main() {
    insecure_func();
    return 0;
}
EOF

    cat << 'EOF' > security.patch
--- waf_engine.c
+++ waf_engine.c
@@ -1,7 +1,7 @@
 #include <stdio.h>
-void insecure_func() {
-    printf("Vulnerable\n");
+void secure_func() {
+    printf("Secured WAF Engine Running\n");
 }
 int main() {
-    insecure_func();
+    secure_func();
     return 0;
 }
EOF

    cat << 'EOF' > Makefile
all: waf_engine

waf_engine: waf_engine.o
	gcc -o waf_engine waf_engine.o $(LDFLAGS)

waf_engine.o: waf_engine.c
	gcc -c waf_engine.c

clean:
	rm -f *.o waf_engine
EOF

    cat << 'EOF' > ci_build.sh
#!/bin/bash

echo "Starting CI Build..."
# TODO: resolve dependencies and set LDFLAGS here

make clean
make

echo "Running tests..."
./waf_engine > build_success.log
EOF
    chmod +x ci_build.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
