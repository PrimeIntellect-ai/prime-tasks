#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr jq fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Generate the video fixture
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=6 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='INC-8832':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,3,4)'" -c:v libx264 /app/server_feed.mp4

    # Create the oracle script
    cat << 'EOF' > /app/oracle_process.sh
#!/bin/bash
jq -c 'select(.level == "CRITICAL")' | while read -r line; do
  log_id=$(echo "$line" | jq -r '.log_id')
  ip=$(echo "$line" | jq -r '.ip' | sed -E 's/^[0-9]+\.[0-9]+/XXX.XXX/')
  msg=$(echo "$line" | jq -r '.message')
  echo "[INC-8832] ID:${log_id} | IP:${ip} | MSG:${msg}"
done
EOF
    chmod +x /app/oracle_process.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
