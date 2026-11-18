#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tar coreutils
    pip3 install pytest

    mkdir -p /app/corpora/evil/item_1
    mkdir -p /app/corpora/evil/item_2
    mkdir -p /app/corpora/evil/item_3
    mkdir -p /app/corpora/evil/item_4

    for i in 1 2 3 4 5; do
        mkdir -p /app/corpora/clean/item_$i
    done

    # Reference video: 142 frames
    ffmpeg -f lavfi -i color=c=black:s=320x240:r=25 -frames:v 142 /app/reference_feed.mp4

    # Evil item 1: Symlink loop
    ln -s b /app/corpora/evil/item_1/a
    ln -s a /app/corpora/evil/item_1/b

    # Evil item 2: Corrupted tar
    echo "corrupted tar file" > /app/corpora/evil/item_2/payload.tar

    # Evil item 3: Fake video file (extracts text, fails JPEG check)
    mkdir -p /tmp/evil3
    echo "This is not a real mp4 file" > /tmp/evil3/video.mp4
    tar -cf /app/corpora/evil/item_3/payload.tar -C /tmp/evil3 video.mp4

    # Evil item 4: 142 frames video
    mkdir -p /tmp/evil4
    ffmpeg -f lavfi -i color=c=red:s=320x240:r=25 -frames:v 142 /tmp/evil4/video.mp4
    tar -cf /app/corpora/evil/item_4/payload.tar -C /tmp/evil4 video.mp4

    # Clean items 1-5: 50 frames video
    for i in 1 2 3 4 5; do
        mkdir -p /tmp/clean$i
        ffmpeg -f lavfi -i color=c=blue:s=320x240:r=25 -frames:v 50 /tmp/clean$i/video.mp4
        tar -cf /app/corpora/clean/item_$i/payload.tar -C /tmp/clean$i video.mp4
    done

    rm -rf /tmp/evil* /tmp/clean*

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
