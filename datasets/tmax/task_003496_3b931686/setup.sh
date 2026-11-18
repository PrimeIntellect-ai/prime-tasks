#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y sqlite3 jq ffmpeg tesseract-ocr fonts-dejavu socat netcat-openbsd curl

    mkdir -p /app
    cd /app

    # 1. Create SQLite DB
    sqlite3 inventory.db <<EOF
CREATE TABLE servers (id TEXT PRIMARY KEY, hostname TEXT);
CREATE TABLE jobs (id TEXT PRIMARY KEY, server_id TEXT, expected_gb INT);
INSERT INTO servers VALUES ('srv-1', 'db-prod-eu');
INSERT INTO servers VALUES ('srv-2', 'db-prod-us');
INSERT INTO jobs VALUES ('A100', 'srv-1', 500);
INSERT INTO jobs VALUES ('B200', 'srv-2', 850);
EOF

    # 2. Create NoSQL JSONL
    cat <<EOF > nosql_dump.jsonl
{"job_id": "A100", "metrics": {"actual_gb": 490}, "status": "SUCCESS"}
{"job_id": "B200", "metrics": {"actual_gb": 845}, "status": "SUCCESS"}
EOF

    # 3. Create Video Fixture
    ffmpeg -y -f lavfi -i "color=c=black:s=640x480:d=5" \
      -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='JOB_ID\: A100':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,1,2)'" \
      -c:v libx264 -pix_fmt yuv420p temp1.mp4

    ffmpeg -y -f lavfi -i "color=c=black:s=640x480:d=5" \
      -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='JOB_ID\: B200':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,1,2)'" \
      -c:v libx264 -pix_fmt yuv420p temp2.mp4

    echo "file 'temp1.mp4'" > list.txt
    echo "file 'temp2.mp4'" >> list.txt
    ffmpeg -y -f concat -safe 0 -i list.txt -c copy dashboard_recording.mp4
    rm temp1.mp4 temp2.mp4 list.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
