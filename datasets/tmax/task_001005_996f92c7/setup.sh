#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip patch gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/ci_system/src
    mkdir -p /home/user/ci_system/submissions

    # Baseline code
    cat << 'EOF' > /home/user/ci_system/src/math_utils.sh
#!/bin/bash
if [ "$1" == "test" ]; then
    res=$(./math_utils.sh add 2 3)
    if [ "$res" != "5" ]; then exit 1; fi
    exit 0
fi

if [ "$1" == "add" ]; then
    echo $(($2 + $3))
fi
EOF
    chmod +x /home/user/ci_system/src/math_utils.sh

    # Submissions
    cd /home/user/ci_system/submissions

    # 01_alice: Valid, ACCEPTED
    cat << 'EOF' > 01_alice.patch
--- a/math_utils.sh
+++ b/math_utils.sh
@@ -6,6 +6,9 @@
     exit 0
 fi

+if [ "$1" == "sub" ]; then
+    echo $(($2 - $3))
+fi
 if [ "$1" == "add" ]; then
     echo $(($2 + $3))
 fi
EOF
    echo "USER=alice" > 01_alice.meta
    echo "TIMESTAMP=1000" >> 01_alice.meta
    echo "CHECKSUM=$(sha256sum 01_alice.patch | awk '{print $1}')" >> 01_alice.meta

    # 02_bob: Checksum fail
    cat << 'EOF' > 02_bob.patch
--- a/math_utils.sh
+++ b/math_utils.sh
@@ -6,6 +6,9 @@
EOF
    echo "USER=bob" > 02_bob.meta
    echo "TIMESTAMP=1010" >> 02_bob.meta
    echo "CHECKSUM=invalidchecksum00000000000000000000000000000000000000000000000" >> 02_bob.meta

    # 03_alice: Rate limited (1030 - 1000 < 60)
    cp 01_alice.patch 03_alice.patch
    echo "USER=alice" > 03_alice.meta
    echo "TIMESTAMP=1030" >> 03_alice.meta
    echo "CHECKSUM=$(sha256sum 03_alice.patch | awk '{print $1}')" >> 03_alice.meta

    # 04_charlie: Patch fail
    cat << 'EOF' > 04_charlie.patch
--- a/nonexistent.sh
+++ b/nonexistent.sh
@@ -1 +1,2 @@
+foo
EOF
    echo "USER=charlie" > 04_charlie.meta
    echo "TIMESTAMP=1000" >> 04_charlie.meta
    echo "CHECKSUM=$(sha256sum 04_charlie.patch | awk '{print $1}')" >> 04_charlie.meta

    # 05_dave: Test fail (breaks addition)
    cat << 'EOF' > 05_dave.patch
--- a/math_utils.sh
+++ b/math_utils.sh
@@ -7,5 +7,5 @@
 fi

 if [ "$1" == "add" ]; then
-    echo $(($2 + $3))
+    echo $(($2 * $3))
 fi
EOF
    echo "USER=dave" > 05_dave.meta
    echo "TIMESTAMP=1000" >> 05_dave.meta
    echo "CHECKSUM=$(sha256sum 05_dave.patch | awk '{print $1}')" >> 05_dave.meta

    # 06_alice: Valid, ACCEPTED (1065 - 1000 >= 60)
    cp 01_alice.patch 06_alice.patch
    echo "USER=alice" > 06_alice.meta
    echo "TIMESTAMP=1065" >> 06_alice.meta
    echo "CHECKSUM=$(sha256sum 06_alice.patch | awk '{print $1}')" >> 06_alice.meta

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
