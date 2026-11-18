#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk coreutils
    pip3 install pytest

    mkdir -p /app
    # Generate a video with exactly 12 frames (T = 12)
    ffmpeg -y -f lavfi -i color=c=red:s=64x64:r=24 -frames:v 12 -c:v libx264 /app/audit_logs.mp4

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/audit_paths_oracle.sh
#!/bin/bash
# T is exactly 12 based on the 12 frames in the video
T=12
awk '{print $1, $2}' "$1" | sort -u | awk '{count[$1]++} END {for (node in count) if (count[node] > '"$T"') print node, count[node]}' | sort -k2,2nr -k1,1
EOF
    chmod +x /opt/oracle/audit_paths_oracle.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
