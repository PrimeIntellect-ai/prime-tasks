#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang espeak ffmpeg
pip3 install pytest

# Create audio file
mkdir -p /app/audio
espeak -w /app/audio/intercept.wav "The payload is ready. Make sure all beacons use the X-Shadow-Protocol header. For the web exploits, just inject an image tag with an onerror handler. That's img space src equals x space onerror equals alert one."

# Create corpus directories
mkdir -p /app/corpus/evil /app/corpus/clean

# Create evil corpus
cat << 'EOF' > /app/corpus/evil/evil_1.txt
GET / HTTP/1.1
Host: example.com
X-Shadow-Protocol: 1

EOF

cat << 'EOF' > /app/corpus/evil/evil_2.txt
GET / HTTP/1.1
Host: example.com

<img src=x onerror=alert(1)>
EOF

cat << 'EOF' > /app/corpus/evil/evil_3.txt
GET /login?password=12345 HTTP/1.1
Host: example.com

EOF

cat << 'EOF' > /app/corpus/evil/evil_4.txt
GET /search?q=' OR 1=1 HTTP/1.1
Host: example.com

EOF

# Create clean corpus
cat << 'EOF' > /app/corpus/clean/clean_1.txt
GET / HTTP/1.1
Host: example.com

EOF

cat << 'EOF' > /app/corpus/clean/clean_2.txt
POST /login HTTP/1.1
Host: example.com
Content-Length: 14

password=12345
EOF

cat << 'EOF' > /app/corpus/clean/clean_3.txt
GET / HTTP/1.1
Host: example.com

<img src=logo.png>
EOF

# Convert line endings to CRLF for HTTP requests
sed -i 's/$/\r/' /app/corpus/evil/*.txt /app/corpus/clean/*.txt

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
