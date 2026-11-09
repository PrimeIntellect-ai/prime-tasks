#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip patch
pip3 install pytest

mkdir -p /home/user/build_system/src
mkdir -p /home/user/build_system/patches
mkdir -p /home/user/build_system/out

cat << 'EOF' > /home/user/build_system/graph.txt
A: B C
B: D
C: D
D: 
EOF

echo "Source A" > /home/user/build_system/src/A.txt
echo "Source B" > /home/user/build_system/src/B.txt
echo "Source C" > /home/user/build_system/src/C.txt
echo "Source D" > /home/user/build_system/src/D.txt

cat << 'EOF' > /home/user/build_system/patches/B.patch
--- src/B.txt
+++ src/B.txt
@@ -1 +1 @@
-Source B
+Source B Patched
EOF

cat << 'EOF' > /home/user/build_system/patches/D.patch
--- src/D.txt
+++ src/D.txt
@@ -1 +1 @@
-Source D
+Source D Patched
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
