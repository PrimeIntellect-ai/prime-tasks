#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++ build-essential
    pip3 install pytest Pillow

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate video and logs using a quick Python script
    cat << 'EOF' > /tmp/setup.py
import os
from PIL import Image
import subprocess

# Generate video frames
os.makedirs('/app/frames', exist_ok=True)
for i in range(60):
    img = Image.new('RGB', (320, 240), color='black')
    if i == 42:
        for x in range(100, 120):
            for y in range(100, 120):
                img.putpixel((x, y), (255, 0, 0))
    img.save(f'/app/frames/frame_{i:03d}.png')

subprocess.run(['ffmpeg', '-y', '-framerate', '1', '-i', '/app/frames/frame_%03d.png', '-c:v', 'libx264', '-r', '1', '-pix_fmt', 'yuv420p', '/app/vnc_capture.mp4'], check=True)

# Generate logs
for i in range(50):
    with open(f'/app/corpus/clean/log_{i}.txt', 'w') as f:
        f.write("Oct 14 12:34:56 server sshd[123]: Accepted publickey for user from 10.0.0.1 port 5000\n")
        f.write("Oct 14 12:34:58 server sshd[123]: Connection closed by authenticating user user 10.0.0.1 port 5000\n")

for i in range(50):
    with open(f'/app/corpus/evil/log_{i}.txt', 'w') as f:
        f.write("Oct 14 12:34:56 server sshd[123]: Accepted publickey for user from 10.0.0.1 port 5000\n")
        f.write("Oct 14 12:34:56 server sshd[123]: Connection closed by authenticating user user 10.0.0.1 port 5000\n")
EOF
    python3 /tmp/setup.py
    rm -rf /app/frames /tmp/setup.py

    # Create mock QEMU script
    cat << 'EOF' > /app/mock_qemu.sh
#!/bin/bash
sleep $((2 + RANDOM % 4))
exit 1
EOF
    chmod +x /app/mock_qemu.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
