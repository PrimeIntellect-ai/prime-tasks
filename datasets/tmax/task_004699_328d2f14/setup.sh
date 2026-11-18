#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/corpora/evil /app/corpora/clean

    # Create corpora
    echo "exploit_payload_v2_bypass" > /app/corpora/evil/payload1.txt
    echo "some_prefix_exploit_payload_v2_bypass_suffix" > /app/corpora/evil/payload2.txt
    echo "benign compliance log" > /app/corpora/clean/log1.txt
    echo "regular service input" > /app/corpora/clean/log2.txt

    # Generate video
    cat << 'EOF' > /tmp/text1.txt
echo "ZXhwbG9pdF9wYXlsb2FkX3YyX2J5cGFzcw==" | nc target 8080
EOF

    cat << 'EOF' > /tmp/text2.txt
iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
EOF

    ffmpeg -f lavfi -i color=c=black:s=800x600:d=25 -vf \
    "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:fontsize=18:fontcolor=white:x=10:y=50:textfile=/tmp/text1.txt:enable='between(t,14,17)', \
     drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:fontsize=18:fontcolor=white:x=10:y=100:textfile=/tmp/text2.txt:enable='between(t,19,22)'" \
    -c:v libx264 -pix_fmt yuv420p /app/incident_record.mp4

    rm /tmp/text1.txt /tmp/text2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
