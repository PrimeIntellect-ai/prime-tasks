#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        ffmpeg \
        fonts-liberation \
        tesseract-ocr

    pip3 install pytest pytesseract opencv-python-headless

    mkdir -p /app

    # The original hidden text (normalized format)
    echo "breaking news global markets rally after new trade agreement signed in geneva several tech stocks surge to record highs" > /app/ground_truth.txt

    # Create a text file with mojibake to render onto the video
    python3 -c '
text = "Breaking News: Global markets rally after new trade agreement signed in Geneva! Several tech stocks surge to record highs..."
mojibake = text.encode("utf-8").decode("latin-1")
with open("/app/scroll.txt", "w", encoding="utf-8") as f:
    f.write(mojibake)
'

    # Generate a 15-second video with scrolling text at the bottom
    ffmpeg -f lavfi -i color=c=blue:s=640x480:d=15 \
      -vf "drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf:textfile=/app/scroll.txt:fontcolor=white:fontsize=36:y=h-40:x=w-t*150" \
      -c:v libx264 -preset ultrafast -pix_fmt yuv420p /app/archive_broadcast.mp4

    # Remove setup artifacts
    rm /app/scroll.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
