#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest

mkdir -p /app
mkdir -p /home/user

# Create a test video (10 seconds, 30fps = 300 frames)
ffmpeg -y -f lavfi -i testsrc=duration=10:size=320x240:rate=30 /app/video.mp4

# Create legacy Python 2 script
cat << 'EOF' > /home/user/legacy_api.py
import sys
import os
import subprocess
import json

def get_frame(frame_num):
    cmd = [
        'ffmpeg', '-y', '-i', '/app/video.mp4', '-vf', 'select=eq(n\\,{})'.format(frame_num),
        '-vframes', '1', '-f', 'image2pipe', '-vcodec', 'pgm', '-'
    ]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = p.communicate()
    return out

def count_bright(pgm_data):
    if not pgm_data: return 0
    lines = pgm_data.split('\n')
    # Skip PGM header
    i = 0
    while i < len(lines) and lines[i] != '255':
        i += 1
    i += 1

    data = '\n'.join(lines[i:])
    count = 0
    for byte in data:
        if ord(byte) > 128:
            count += 1
    return count

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print "Error"
        sys.exit(1)

    frame_num = int(sys.argv[1])
    raw_frame = get_frame(frame_num)
    brights = count_bright(raw_frame)

    print json.dumps({"frame": frame_num, "bright_pixels": brights})
EOF

# Create oracle (Python 3 reference)
cat << 'EOF' > /app/oracle_py.py
import sys
import subprocess
import json

def get_frame(frame_num):
    cmd = [
        'ffmpeg', '-y', '-i', '/app/video.mp4', '-vf', f'select=eq(n\\,{frame_num})',
        '-vframes', '1', '-f', 'image2pipe', '-vcodec', 'pgm', '-'
    ]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = p.communicate()
    return out

def count_bright(pgm_data):
    if not pgm_data: return 0
    parts = pgm_data.split(b'\n', 3)
    if len(parts) < 4: return 0
    idx = pgm_data.find(b'255\n')
    if idx == -1: return 0
    pixels = pgm_data[idx+4:]
    return sum(1 for b in pixels if b > 128)

if __name__ == '__main__':
    frame_num = int(sys.argv[1])
    raw_frame = get_frame(frame_num)
    brights = count_bright(raw_frame)
    print(json.dumps({"frame": frame_num, "bright_pixels": brights}))
EOF

chmod +x /app/oracle_py.py
cat << 'EOF' > /app/oracle_bin
#!/bin/bash
python3 /app/oracle_py.py "$1"
EOF
chmod +x /app/oracle_bin

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
