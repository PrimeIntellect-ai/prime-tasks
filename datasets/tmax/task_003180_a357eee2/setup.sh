#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang ffmpeg
    pip3 install pytest PyJWT

    mkdir -p /app/uploads
    mkdir -p /home/user

    # Generate incident_logs.mp4
    # Create frames with text
    mkdir -p /tmp/frames
    for i in $(seq 1 150); do
        if [ $i -ge 120 ] && [ $i -le 150 ]; then
            TEXT="JWT_SIGNING_SECRET=\"s3cr3t_k3y_v3ry_s3cur3_1337\""
        else
            TEXT="Scrolling terminal text... frame $i"
        fi
        # Create a simple image using ffmpeg directly or by generating a text file and using drawtext
        echo "$TEXT" > /tmp/frames/frame_$i.txt
    done

    # We can just use ffmpeg to generate a video with drawtext
    # To keep it simple without complex drawtext, we will just use a python script to generate images or a simple ffmpeg command
    cat << 'EOF' > /tmp/gen_video.py
import subprocess
import os

os.makedirs('/tmp/img', exist_ok=True)
for i in range(1, 151):
    text = 'JWT_SIGNING_SECRET="s3cr3t_k3y_v3ry_s3cur3_1337"' if 120 <= i <= 150 else f'Scrolling terminal text... frame {i}'
    cmd = [
        'ffmpeg', '-y', '-f', 'lavfi', '-i', 'color=c=black:s=640x480', 
        '-vf', f"drawtext=text='{text}':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2",
        '-frames:v', '1', f'/tmp/img/img_{i:03d}.png'
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

subprocess.run([
    'ffmpeg', '-y', '-framerate', '30', '-i', '/tmp/img/img_%03d.png',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '/app/incident_logs.mp4'
], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
EOF
    python3 /tmp/gen_video.py

    # Generate uploads and ground truth
    cat << 'EOF' > /tmp/gen_data.py
import os
import json
import subprocess

out_dir = '/app/uploads'
os.makedirs(out_dir, exist_ok=True)
truth = {}

def make_elf(arch, key_type, key_data, out_path):
    # Create dummy c file
    with open('/tmp/dummy.c', 'w') as f:
        f.write("int main() { return 0; }\n")

    # Compile
    m = '-m32' if arch == 32 else '-m64'
    subprocess.run(['gcc', m, '/tmp/dummy.c', '-o', '/tmp/dummy.elf'])

    # Add custom section
    with open('/tmp/key.bin', 'wb') as f:
        f.write(f"{key_type} {key_data} user@host\n".encode())

    subprocess.run(['objcopy', '--add-section', '.ssh_pubkey=/tmp/key.bin', '/tmp/dummy.elf', out_path])

subprocess.run(['apt-get', 'install', '-y', 'gcc', 'gcc-multilib', 'binutils'])

for i in range(1, 101):
    req_name = f"req_{i:03d}.req"
    req_path = os.path.join(out_dir, req_name)

    is_safe = True
    filename = "upload.elf"
    arch = 64
    key_type = "ssh-ed25519"
    key_data = "AAAAC3NzaC1lZDI1NTE5AAAAI...dummy"

    if i <= 20:
        filename = "../../../etc/authorized_keys"
        is_safe = False
    elif i <= 40:
        key_type = "ssh-rsa"
        is_safe = False
    elif i <= 50:
        arch = 32
        is_safe = False

    elf_path = f"/tmp/{req_name}.elf"
    make_elf(arch, key_type, key_data, elf_path)

    with open(elf_path, 'rb') as f:
        elf_data = f.read()

    with open(req_path, 'wb') as f:
        f.write(b"POST /upload HTTP/1.1\r\n")
        f.write(b"Content-Type: multipart/form-data; boundary=----WebKitFormBoundary\r\n\r\n")
        f.write(b"------WebKitFormBoundary\r\n")
        f.write(f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n\r\n'.encode())
        f.write(elf_data)
        f.write(b"\r\n------WebKitFormBoundary--\r\n")

    truth[req_name] = is_safe

with open('/app/.ground_truth.json', 'w') as f:
    json.dump(truth, f)
EOF
    python3 /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
