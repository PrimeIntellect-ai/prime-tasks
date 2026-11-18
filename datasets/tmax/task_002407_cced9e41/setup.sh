#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest websockets

    # Create directories
    mkdir -p /app/corpora/clean_patches
    mkdir -p /app/corpora/evil_patches

    # Generate the architect voicemail audio file using espeak
    espeak -w /app/architect_voicemail.wav "Listen closely. The polyglot websocket server needs to be configured to listen on port eight seven six five. Also, because this runs on edge nodes, ensure the memory limit is strictly fifty megabytes."

    # Create clean patches
    cat << 'EOF' > /app/corpora/clean_patches/clean1.diff
--- src/main.c
+++ src/main.c
@@ -1,2 +1,3 @@
 #include <stdio.h>
+
 int main() { return 0; }
EOF

    cat << 'EOF' > /app/corpora/clean_patches/clean2.diff
--- src/utils/helper.py
+++ src/utils/helper.py
@@ -10,2 +10,3 @@
 def add(a, b):
-    return a + b
+    res = a + b
+    return res
EOF

    # Create evil patches (directory traversal / out-of-bounds)
    cat << 'EOF' > /app/corpora/evil_patches/evil1.diff
--- src/../../../etc/shadow
+++ src/../../../etc/shadow
@@ -1,2 +1,3 @@
 root:*:18800:0:99999:7:::
+hacker::18800:0:99999:7:::
EOF

    cat << 'EOF' > /app/corpora/evil_patches/evil2.diff
--- src/../.git/config
+++ src/../.git/config
@@ -5,2 +5,3 @@
 [remote "origin"]
     url = https://github.com/user/repo.git
+    url = https://evil.com/repo.git
EOF

    cat << 'EOF' > /app/corpora/evil_patches/evil3.diff
--- /var/www/html/index.php
+++ /var/www/html/index.php
@@ -1,2 +1,3 @@
 <?php
+echo "hacked";
 ?>
EOF

    # Set up user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
