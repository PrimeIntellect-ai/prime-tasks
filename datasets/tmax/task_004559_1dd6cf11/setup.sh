#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc ffmpeg
pip3 install pytest

# Create directories
mkdir -p /app/corpora/clean
mkdir -p /app/corpora/evil
mkdir -p /app/video_source

# Generate the video fixture frames using Python to avoid extra dependencies
python3 -c '
import os
os.makedirs("/app/video_source", exist_ok=True)
colors = [255, 0, 128, 64, 192]
for i, c in enumerate(colors, 1):
    with open(f"/app/video_source/f{i}.pgm", "w") as f:
        f.write(f"P2\n100 100\n255\n")
        f.write(" ".join([str(c)] * 10000))
'

# Encode the video
ffmpeg -y -framerate 1 -i /app/video_source/f%d.pgm -c:v libx264 -pix_fmt yuv420p /app/experiment_run.mp4

# Generate Adversarial Corpus
# Clean files
cat << 'EOF' > /app/corpora/clean/config1.txt
learning_rate=0.01
batch_size=32
cv_folds=5
EOF

cat << 'EOF' > /app/corpora/clean/config2.txt
learning_rate=1.0
batch_size=256
cv_folds=10
EOF

cat << 'EOF' > /app/corpora/clean/config3.txt
cv_folds=2
batch_size=8
learning_rate=0.0001
EOF

# Evil files
cat << 'EOF' > /app/corpora/evil/bad1.txt
# missing cv_folds
learning_rate=0.01
batch_size=32
EOF

cat << 'EOF' > /app/corpora/evil/bad2.txt
# learning rate too high
learning_rate=1.01
batch_size=64
cv_folds=3
EOF

cat << 'EOF' > /app/corpora/evil/bad3.txt
# batch size not power of 2 from the allowed list
learning_rate=0.5
batch_size=60
cv_folds=4
EOF

cat << 'EOF' > /app/corpora/evil/bad4.txt
# unknown key
learning_rate=0.1
batch_size=16
cv_folds=5
optimizer=adam
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
