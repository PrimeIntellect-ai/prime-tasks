#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/corpus/clean /home/user/corpus/evil
mkdir -p /app

# Create clean corpus
cat << 'EOF' > /home/user/corpus/clean/1.txt
BEGIN_ARTIFACT
DEP react 18.2.0
DEP lodash 4.17.21
FFI_BIND /usr/include/math.h
END_ARTIFACT
EOF

cat << 'EOF' > /home/user/corpus/clean/2.txt
BEGIN_ARTIFACT
DEP rust-lib 1.0.0
FFI_BIND /opt/app/headers/bindings.h
END_ARTIFACT
EOF

# Create evil corpus
cat << 'EOF' > /home/user/corpus/evil/1.txt
BEGIN_ARTIFACT
DEP react 18.2.0
FFI_BIND /usr/include/../../etc/passwd
END_ARTIFACT
EOF

cat << 'EOF' > /home/user/corpus/evil/2.txt
BEGIN_ARTIFACT
DEP lodash `<script>alert(1)</script>`
FFI_BIND /usr/include/math.h
END_ARTIFACT
EOF

cat << 'EOF' > /home/user/corpus/evil/3.txt
BEGIN_ARTIFACT
FFI_BIND /usr/include/math.h
DEP react 18.2.0
END_ARTIFACT
EOF

cat << 'EOF' > /home/user/corpus/evil/4.txt
BEGIN_ARTIFACT
DEP pkg 1.0
FFI_BIND /usr/include/math.h
EOF

# Dummy stripped binary
cat << 'EOF' > /tmp/deps_compiler.c
#include <stdio.h>
int main() { return 0; }
EOF
gcc -O2 -s /tmp/deps_compiler.c -o /app/deps_compiler
rm /tmp/deps_compiler.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
