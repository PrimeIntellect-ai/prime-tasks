#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick build-essential
pip3 install pytest

mkdir -p /app
cd /app

# Generate the image fixture
cat << 'EOF' > /tmp/mapping.txt
A: 1
B: 2
C: 3
D: 4
E: 5
EOF
# Avoid ImageMagick @ policy error by passing text directly
convert -background white -fill black -font Courier -pointsize 24 label:"$(cat /tmp/mapping.txt)" /app/mapping.png

# Generate training data
cat << 'EOF' > /app/events.csv
id,event_sequence
1,A B C D E
2,A A B C
3,B D E A
4,C E E
5,A B D
6,E D C B A
7,A C E
8,B B B
9,D A C
10,E A B C D
EOF

# Generate test data
cat << 'EOF' > /app/test_events.csv
id,event_sequence
1,A B E
2,C D A
3,E E
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
