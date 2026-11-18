#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg jq
pip3 install pytest

mkdir -p /app/corpus/clean /app/corpus/evil

cat << 'EOF' > /app/corpus/clean/c1.json
{"speaker": "Speaker 1", "duration": 5.5, "transcript": "Hello world."}
EOF
cat << 'EOF' > /app/corpus/clean/c2.json
{"speaker": "Guest", "duration": 100.0, "transcript": "This is a valid transcript."}
EOF
cat << 'EOF' > /app/corpus/clean/c3.json
{"speaker": "Host", "duration": 1.0, "transcript": "Good morning."}
EOF

cat << 'EOF' > /app/corpus/evil/e1.json
{"duration": 10.0, "transcript": "Hello world."}
EOF
cat << 'EOF' > /app/corpus/evil/e2.json
{"speaker": "", "duration": 10.0, "transcript": "Hello world."}
EOF
cat << 'EOF' > /app/corpus/evil/e3.json
{"speaker": null, "duration": 10.0, "transcript": "Hello world."}
EOF

cat << 'EOF' > /app/corpus/evil/e4.json
{"speaker": "A", "duration": 0.99, "transcript": "Too short"}
EOF
cat << 'EOF' > /app/corpus/evil/e5.json
{"speaker": "A", "duration": 100.1, "transcript": "Too long"}
EOF
cat << 'EOF' > /app/corpus/evil/e6.json
{"speaker": "A", "duration": -5.0, "transcript": "Negative"}
EOF

cat << 'EOF' > /app/corpus/evil/e7.json
{"speaker": "A", "duration": 10.0, "transcript": "well thank you for watching this video"}
EOF
cat << 'EOF' > /app/corpus/evil/e8.json
{"speaker": "A", "duration": 10.0, "transcript": "subtitles by amara"}
EOF

ffmpeg -f lavfi -i sine=frequency=1000:duration=45.123456 -c:a pcm_s16le /app/interview.wav

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
