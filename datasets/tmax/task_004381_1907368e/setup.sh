#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app/evidence

    # Create the C source file for the custom hash tool
    cat << 'EOF' > /tmp/auth_tool.c
#include <stdio.h>
#include <stdlib.h>

unsigned int custom_hash(const unsigned char *data, size_t len) {
    unsigned int hash = 0x1337BEEF;
    for (size_t i = 0; i < len; i++) {
        hash ^= data[i];
        hash = (hash << 3) | (hash >> 29); // Left rotate by 3
    }
    return hash;
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char *buf = malloc(len);
    fread(buf, 1, len, f);
    fclose(f);
    printf("%08x\n", custom_hash(buf, len));
    free(buf);
    return 0;
}
EOF

    # Compile and strip the binary
    gcc -O2 -s /tmp/auth_tool.c -o /app/auth_tool
    rm /tmp/auth_tool.c

    # Create some sample HTML snippets in the evidence directory
    cat << 'EOF' > /app/evidence/snippet_01.html
<!DOCTYPE html>
<html>
<head>
    <title>Safe Page</title>
    <script src="https://cdn.trusted.com/main.js"></script>
</head>
<body>
    <h1>Welcome</h1>
</body>
</html>
EOF

    cat << 'EOF' > /app/evidence/snippet_02.html
<!DOCTYPE html>
<html>
<head>
    <title>Compromised Page</title>
</head>
<body>
    <h1>Welcome</h1>
    <script>alert('XSS');</script>
</body>
</html>
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
