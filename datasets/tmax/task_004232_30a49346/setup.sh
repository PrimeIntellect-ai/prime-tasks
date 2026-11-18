#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick gawk socat netcat-openbsd curl
    pip3 install pytest

    mkdir -p /app/frames
    # Generate 10 frames (100x100 resolution)
    for i in $(seq 1 10); do
        # Calculate intensities (Base + Frame_Index * Slope)
        val_00=$(( 10 + i * 10 ))
        val_10=$(( 20 + i * 20 ))
        val_01=$(( 10 + i * 5 ))
        val_11=50

        # Create a 2x2 PGM then scale it up to 100x100 without interpolation so it is a clear grid
        printf "P2\n2 2\n255\n%d %d\n%d %d\n" $val_00 $val_10 $val_01 $val_11 > /app/frames/raw_${i}.pgm
        convert /app/frames/raw_${i}.pgm -scale 100x100 /app/frames/frame_$(printf "%04d" $i).jpg
    done

    # Compile into mp4
    ffmpeg -framerate 1 -i /app/frames/frame_%04d.jpg -c:v libx264 -pix_fmt yuv420p /app/microarray_signal.mp4
    rm -rf /app/frames

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
