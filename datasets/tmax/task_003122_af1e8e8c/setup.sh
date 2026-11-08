#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc build-essential
pip3 install pytest

mkdir -p /home/user/project
cd /home/user/project

cat << 'EOF' > url_sanitizer.c
#include <string.h>

void sanitize_path(const char* in, char* out) {
    if (strstr(in, "../")) {
        strcpy(out, "/SECURE_ROUTING_ERROR");
    } else {
        strcpy(out, in);
    }
}
EOF

cat << 'EOF' > main.c
#include <stdio.h>

void sanitize_path(const char* in, char* out);

int main(int argc, char **argv) {
    if(argc < 2) return 1;
    char out[256];
    sanitize_path(argv[1], out);
    printf("%s\n", out);
    return 0;
}
EOF

cat << 'EOF' > build.sh
#!/bin/bash
gcc -c url_sanitizer.c -o url_sanitizer.o
gcc -shared -o liburlsanitizer.so url_sanitizer.o
gcc main.c -o url_tool -L. -lurlsanitizer
EOF
chmod +x build.sh

cat << 'EOF' > test_routing.sh
#!/bin/bash
URL=$1
# Extracts the path from the URL, but leaves the query parameters attached!
PATH_PART=$(echo "$URL" | sed -e 's|https*://[^/]*||')

RESULT=$(./url_tool "$PATH_PART")
echo "$RESULT"
EOF
chmod +x test_routing.sh

cat << 'EOF' > ci_run.sh
#!/bin/bash

./build.sh

# Integration tests
TEST1=$(./test_routing.sh "http://example.com/api/v1/users")
if [ "$TEST1" != "/api/v1/users" ]; then
    echo "Test 1 Failed: Expected /api/v1/users, got $TEST1"
    exit 1
fi

TEST2=$(./test_routing.sh "http://example.com/api/../passwd?token=admin")
if [ "$TEST2" != "/SECURE_ROUTING_ERROR" ]; then
    echo "Test 2 Failed: Expected /SECURE_ROUTING_ERROR, got $TEST2"
    exit 1
fi

echo "CI SUCCESS" > ci_success.log
EOF
chmod +x ci_run.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
