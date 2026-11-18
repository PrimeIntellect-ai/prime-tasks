#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip patch
    pip3 install pytest

    mkdir -p /home/user/qa_env/patches

    cat << 'EOF' > /home/user/qa_env/test_case.lt
ALLOC X
ALLOC Y
USE X
FREE X
USE Y
ALLOC Z
USE X
FREE Y
FREE Z
EOF

    cat << 'EOF' > /home/user/qa_env/patches/patch_7.diff
--- test_case.lt
+++ test_case.lt
@@ -5,5 +5,4 @@
 USE Y
 ALLOC Z
-USE X
 FREE Y
 FREE Z
EOF

    cat << 'EOF' > /home/user/qa_env/patches/patch_1.diff
--- test_case.lt
+++ test_case.lt
@@ -5,5 +5,5 @@
 USE Y
 ALLOC Z
 USE X
+FREE X
 FREE Y
 FREE Z
EOF

    for i in 2 3 4 5 6 8 9 10; do
        cat << EOF > /home/user/qa_env/patches/patch_$i.diff
--- test_case.lt
+++ test_case.lt
@@ -1,2 +1,3 @@
 ALLOC X
+ALLOC X
 ALLOC Y
EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
