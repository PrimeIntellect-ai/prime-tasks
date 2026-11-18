#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr g++ binutils
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create clean corpus
    echo "(2+2)*4" > /app/corpus/clean/1.txt
    echo "1234^9999" > /app/corpus/clean/2.txt
    echo "abs(-5)" > /app/corpus/clean/3.txt

    # Create evil corpus
    echo "eval('os.system(\"ls\")')" > /app/corpus/evil/1.txt
    echo "((((((5+5))))))" > /app/corpus/evil/2.txt
    echo "99999^1" > /app/corpus/evil/3.txt
    python3 -c 'print("1+" * 150)' > /app/corpus/evil/4.txt

    # Create video with embedded text
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=1 -vf "drawtext=text='AUTH_TOKEN\: 9F8A-7B6C-5D4E-3F2A':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(n,10,24)'" -c:v libx264 /app/e2e_test_run.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
