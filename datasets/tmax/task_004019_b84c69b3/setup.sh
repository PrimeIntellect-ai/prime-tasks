#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3 socat netcat-openbsd curl jq
    pip3 install pytest requests

    mkdir -p /app

    # Generate surveillance video with flashes at 12.0s, 25.5s, 48.2s
    ffmpeg -f lavfi -i "color=c=black:s=320x240:d=50" \
        -vf "drawbox=x=0:y=0:w=320:h=240:color=white:t=fill:enable='between(t,12.0,12.1)+between(t,25.5,25.6)+between(t,48.2,48.3)'" \
        -c:v libx264 -pix_fmt yuv420p -y /app/surveillance.mp4

    # Create network logs CSV
    cat << 'EOF' > /app/network_logs.csv
timestamp,src_ip,dst_ip,bytes
10.5,192.168.1.5,10.0.0.2,500
12.2,10.0.0.2,10.0.0.3,1500
15.0,10.0.0.3,10.0.0.4,200
25.4,192.168.1.10,10.0.0.5,800
40.0,10.0.0.5,10.0.0.6,300
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
