#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil /app/corpora/eval_clean /app/corpora/eval_evil

    # Generate clean and evil corpora
    for i in $(seq 1 20); do
        # Clean images (fractal noise)
        convert -size 100x100 plasma:fractal /app/corpora/clean/img_$(printf "%02d" $i).png
        convert -size 100x100 plasma:fractal /app/corpora/eval_clean/img_$(printf "%02d" $i).png

        # Evil images (black)
        convert -size 100x100 xc:black /app/corpora/evil/img_$(printf "%02d" $i).png
        convert -size 100x100 xc:black /app/corpora/eval_evil/img_$(printf "%02d" $i).png
    done

    # Generate 10s video with black frames at t=4, 5, and 8
    # Using between(t, 3.5, 5.5) covers frames extracted at t=4 and t=5
    # Using between(t, 7.5, 8.5) covers frame extracted at t=8
    ffmpeg -y -f lavfi -i testsrc=duration=10:size=320x240:rate=30 \
        -vf "drawbox=x=0:y=0:w=320:h=240:color=black:t=fill:enable='between(t,3.5,5.5)+between(t,7.5,8.5)'" \
        -c:v libx264 -pix_fmt yuv420p /app/rollout.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
