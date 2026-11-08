#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        fonts-dejavu-core \
        tesseract-ocr \
        libtesseract-dev \
        libgl1-mesa-glx \
        libglib2.0-0

    pip3 install pytest opencv-python pytesseract

    mkdir -p /app/corpora/evil /app/corpora/clean

    # Create the video
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=10:r=24 \
        -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='DEADLOCK_ALERT TX_8432':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='eq(n\,142)'" \
        -c:v libx264 -pix_fmt yuv420p /app/db_monitor.mp4

    # Create clean corpus
    cat << 'EOF' > /app/corpora/clean/clean1.json
{
  "active_transactions": [
    {
      "tx_id": "T1",
      "holds_locks_on": ["A"],
      "waiting_for_locks_on": ["B"]
    },
    {
      "tx_id": "T2",
      "holds_locks_on": ["B"],
      "waiting_for_locks_on": ["C"]
    },
    {
      "tx_id": "T3",
      "holds_locks_on": ["C"],
      "waiting_for_locks_on": []
    }
  ]
}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpora/evil/evil1.json
{
  "active_transactions": [
    {
      "tx_id": "T1",
      "holds_locks_on": ["A"],
      "waiting_for_locks_on": ["B"]
    },
    {
      "tx_id": "T2",
      "holds_locks_on": ["B"],
      "waiting_for_locks_on": ["C"]
    },
    {
      "tx_id": "T3",
      "holds_locks_on": ["C"],
      "waiting_for_locks_on": ["A"]
    }
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
