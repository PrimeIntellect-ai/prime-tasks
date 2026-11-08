#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc ffmpeg
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate dummy video
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x360:rate=30 -c:v libx264 /app/video.mp4

    # Generate clean patches
    for i in $(seq 1 10); do
        cat <<EOF > /app/corpus/clean/patch_${i}.patch
--- a/file${i}.txt
+++ b/file${i}.txt
@@ -1,3 +1,3 @@
 line1
-line2
+line2 updated
 line3
EOF
    done

    # Generate evil patches (RESTRICTED)
    for i in $(seq 1 5); do
        cat <<EOF > /app/corpus/evil/patch_res_${i}.patch
--- a/file${i}.txt
+++ b/file${i}.txt
@@ -1,3 +1,3 @@
 line1
-line2
+line2 updated [RESTRICTED]
 line3
EOF
    done

    # Generate evil patches (METADATA)
    for i in $(seq 6 10); do
        cat <<EOF > /app/corpus/evil/patch_meta_${i}.patch
--- a/file${i}.txt
+++ b/file${i}.txt
@@ -1,3 +1,3 @@
 line1
-line2 [METADATA]
+line2 updated
 line3
EOF
    done

    # Create user and working directory
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/videdit
    chmod -R 777 /home/user
    chmod -R 777 /app
