#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/analysis_env
    mkdir -p /home/user/analysis
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Create conflicting requirements.txt
    cat << 'EOF' > /home/user/analysis_env/requirements.txt
numpy>=1.22.0
scipy==1.4.1
pandas
EOF

    # Create decompiled logic script
    cat << 'EOF' > /home/user/analysis/decompiled_logic.py
def evaluate_payload(payload_data, init_vector):
    x = init_vector[0]
    for val in payload_data:
        fx = x**2 - val
        dfx = 2 * x  # Missing epsilon here, e.g., + 1e-8
        x = x - fx / dfx
    return x
EOF

    # Create sandbox video using ffmpeg
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=5 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:fontsize=20:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:text='[0.450, 1.225, -0.890]':enable='between(t,4,5)'" -c:v libx264 /app/sandbox_run.mp4

    # Create dummy corpus files
    echo "1.5, 2.5, 3.5" > /app/corpus/clean/payload1.dat
    echo "4.0, 5.0, 6.0" > /app/corpus/clean/payload2.dat
    echo "-1.0, 0.0, -2.0" > /app/corpus/evil/payload1.dat
    echo "0.0, 0.0, 0.0" > /app/corpus/evil/payload2.dat

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
