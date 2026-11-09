#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        patch \
        netcat-openbsd \
        curl \
        socat \
        gawk \
        coreutils

    pip3 install pytest

    mkdir -p /app/manifests

    # Generate release_token.png
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 36 -fill black -draw "text 10,50 'REL-8492-SEC'" /app/release_token.png

    # Create CSV parts
    cat << 'EOF' > /app/manifests/part1.csv
ArtifactID,Name,Version
A100,Backend,1.0.0
A103,Frontend,2.1.0
EOF

    cat << 'EOF' > /app/manifests/part2.csv
ArtifactID,Name,Version
A101,Database,1.5.2
A105,Cache,3.0.0
EOF

    cat << 'EOF' > /app/manifests/part3.csv
ArtifactID,Name,Version
A102,Auth,1.1.1
A104,Logger,1.0.5
EOF

    # Create patch file
    cat << 'EOF' > /app/updates.patch
--- merged_manifest.csv	2023-10-01 12:00:00.000000000 +0000
+++ merged_manifest_updated.csv	2023-10-01 12:01:00.000000000 +0000
@@ -2,3 +2,3 @@
 A100,Backend,1.0.0
-A101,Database,1.5.2
+A101,Database,1.6.0
 A102,Auth,1.1.1
@@ -6,2 +6,2 @@
-A104,Logger,1.0.5
+A104,Logger,1.1.0
 A105,Cache,3.0.0
EOF

    # Create release.log
    cat << 'EOF' > /app/release.log
ERROR: CODE_12
ERROR: CODE_15
ERROR: CODE_12
ERROR: CODE_99
ERROR: CODE_15
EOF

    # Create process_logs.sh
    cat << 'EOF' > /app/process_logs.sh
#!/bin/bash
# Inefficient script to find unique errors
declare -a errors
while IFS= read -r line; do
    if [[ $line == ERROR* ]]; then
        found=0
        for e in "${errors[@]}"; do
            if [[ "$e" == "$line" ]]; then
                found=1
                break
            fi
        done
        if [ $found -eq 0 ]; then
            errors+=("$line")
        fi
    fi
done < /app/release.log

for e in "${errors[@]}"; do
    echo "$e"
done
EOF
    chmod +x /app/process_logs.sh

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
