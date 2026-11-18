#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends python3 python3-pip ffmpeg tar zip unzip
pip3 install pytest

mkdir -p /app/corpora/clean
mkdir -p /app/corpora/evil
mkdir -p /home/user

# Generate system_limits.mp4
cat << 'EOF' > /tmp/make_video.py
import os
import subprocess

width, height = 64, 64
fps = 10
frames = 100
red_frames = 5
blue_frames = 42

with open('/tmp/raw_video.rgb', 'wb') as f:
    for i in range(frames):
        if i < red_frames:
            color = bytes([255, 0, 0])
        elif i < red_frames + blue_frames:
            color = bytes([0, 0, 255])
        else:
            color = bytes([0, 0, 0])
        f.write(color * (width * height))

subprocess.run([
    'ffmpeg', '-y',
    '-f', 'rawvideo',
    '-pixel_format', 'rgb24',
    '-video_size', f'{width}x{height}',
    '-framerate', str(fps),
    '-i', '/tmp/raw_video.rgb',
    '-c:v', 'libx264',
    '-pix_fmt', 'yuv444p',
    '/app/system_limits.mp4'
], check=True)
EOF
python3 /tmp/make_video.py

# Create config template
cat << 'EOF' > /home/user/config_template.json
{
  "max_depth": PLACEHOLDER_DEPTH,
  "max_files": PLACEHOLDER_FILES
}
EOF

# Create Evil Corpus
cd /app/corpora/evil

# 1. absolute_path.tar.gz
mkdir -p /tmp/abs_path
touch /tmp/abs_path/test
tar -czf absolute_path.tar.gz -P /etc/shadow 2>/dev/null || true
# Alternatively, create manually with python
cat << 'EOF' > /tmp/make_evil.py
import tarfile
import zipfile
import os

# 1. absolute_path.tar.gz
with tarfile.open("absolute_path.tar.gz", "w:gz") as tar:
    ti = tarfile.TarInfo(name="/etc/shadow")
    ti.size = 0
    tar.addfile(ti)

# 2. traversal.zip
with zipfile.ZipFile("traversal.zip", "w") as z:
    z.writestr("dataset/../../root/.bashrc", "")

# 3. too_many_files.tar.gz
with tarfile.open("too_many_files.tar.gz", "w:gz") as tar:
    for i in range(43):
        ti = tarfile.TarInfo(name=f"file_{i}.txt")
        ti.size = 0
        tar.addfile(ti)

# 4. symlink_loop.tar.gz
with tarfile.open("symlink_loop.tar.gz", "w:gz") as tar:
    for i in range(6):
        ti = tarfile.TarInfo(name=f"link{chr(65+i)}")
        ti.type = tarfile.SYMTYPE
        ti.linkname = f"link{chr(65+(i+1)%6)}"
        tar.addfile(ti)

# 5. symlink_escape.zip
with zipfile.ZipFile("symlink_escape.zip", "w") as z:
    zi = zipfile.ZipInfo("pointer")
    zi.create_system = 3
    zi.external_attr = 0xA1ED0000 # symlink
    z.writestr(zi, "../../../etc/passwd")
EOF
python3 /tmp/make_evil.py

# Create Clean Corpus
cd /app/corpora/clean

cat << 'EOF' > /tmp/make_clean.py
import tarfile
import zipfile

# 1. normal_dataset.tar.gz
with tarfile.open("normal_dataset.tar.gz", "w:gz") as tar:
    for i in range(10):
        ti = tarfile.TarInfo(name=f"data/file{i}.txt")
        ti.size = 0
        tar.addfile(ti)

# 2. safe_symlinks.zip
with zipfile.ZipFile("safe_symlinks.zip", "w") as z:
    for i in range(5):
        z.writestr(f"data/file{i}.txt", "")
    zi = zipfile.ZipInfo("latest")
    zi.create_system = 3
    zi.external_attr = 0xA1ED0000 # symlink
    z.writestr(zi, "data/file1.txt")

# 3. exact_max_files.tar.gz
with tarfile.open("exact_max_files.tar.gz", "w:gz") as tar:
    for i in range(42):
        ti = tarfile.TarInfo(name=f"file_{i}.txt")
        ti.size = 0
        tar.addfile(ti)
EOF
python3 /tmp/make_clean.py

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
chmod -R 777 /app
