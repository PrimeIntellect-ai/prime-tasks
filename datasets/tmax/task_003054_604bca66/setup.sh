#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        imagemagick \
        fonts-dejavu-core \
        tesseract-ocr

    pip3 install pytest

    # Create directories
    mkdir -p /app/frames
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Configure ImageMagick policy to allow text to image
    sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/' /etc/ImageMagick-6/policy.xml || true

    # Generate frames with text
    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 20 -fill black -annotate +10+50 'curl http://admin:supersecret99@10.0.0.1/api/login' /app/frames/frame1.png
    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 20 -fill black -annotate +10+50 'export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE' /app/frames/frame2.png
    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 20 -fill black -annotate +10+50 'sudo -l' /app/frames/frame3.png

    # Encode to mp4 (1 fps, 3 seconds = 3 frames)
    ffmpeg -framerate 1 -i /app/frames/frame%d.png -c:v libx264 -r 1 -pix_fmt yuv420p /app/admin_session.mp4
    rm -rf /app/frames

    # Populate corpora
    cat << 'EOF' > /app/corpora/evil/test1.txt
Something happened here.
curl http://user:mypassword123@api.service.com/data
export AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF
EOF

    cat << 'EOF' > /app/corpora/evil/test2.txt
https://admin:secret_token@dashboard.local
AKIAZZZZZZZZZZZZZZZZ
EOF

    cat << 'EOF' > /app/corpora/clean/test1.txt
This is a clean log file.
No secrets here.
http://example.com/api
AKIA_not_a_real_key_because_too_short
EOF

    cat << 'EOF' > /app/corpora/clean/test2.txt
Another clean file.
user:pass is not a URL here.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
