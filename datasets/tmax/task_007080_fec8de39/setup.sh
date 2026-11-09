#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    mkdir -p /home/user

    # Create the test patch file
    cat << 'EOF' > /home/user/test.patch
--- src/main.rs	2023-10-01 12:00:00.000000000 +0000
+++ src/main.rs	2023-10-01 12:05:00.000000000 +0000
@@ -10,5 +10,5 @@
 fn main() {
     let x = 5;
-    println!("Old value: {}", x);
+    println!("New value: {}", x + 1);
     return;
 }
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
