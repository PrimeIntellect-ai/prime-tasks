#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk coreutils bc
    pip3 install pytest pandas numpy

    mkdir -p /app

    # Generate a sample video
    ffmpeg -f lavfi -i "mandelbrot=size=320x240:rate=1" -t 60 -pix_fmt yuv420p /app/traffic.mp4

    # Generate sensor data
    echo "timestamp_sec,sensor_id,ambient_temp" > /app/sensor_data.csv
    for i in $(seq 0 100); do
        echo "$i,SENS_$((i % 5 + 1)),$((20 + i % 15))" >> /app/sensor_data.csv
    done

    # Generate ground truth anomalies
    mkdir -p /tmp/frames
    ffmpeg -i /app/traffic.mp4 -vf "fps=1,scale=1:1" -f image2 -vcodec rawvideo -pix_fmt rgb24 /tmp/frames/frame_%03d.raw

    echo "timestamp_sec,sensor_id,euclidean_distance" > /app/ground_truth_anomalies.csv
    for f in /tmp/frames/frame_*.raw; do
        idx=$(basename $f | sed 's/frame_0*//;s/\.raw//')
        if [ -z "$idx" ]; then idx=0; fi
        ts=$((idx - 1))

        rgb=$(od -v -t u1 -N 3 "$f" | head -n 1 | awk '{print $2, $3, $4}')
        r=$(echo "$rgb" | awk '{print $1}')
        g=$(echo "$rgb" | awk '{print $2}')
        b=$(echo "$rgb" | awk '{print $3}')

        dist=$(awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN{print sqrt((r-110)^2 + (g-115)^2 + (b-120)^2)}')
        is_anomaly=$(awk -v d="$dist" 'BEGIN{if(d>35.0) print 1; else print 0}')

        if [ "$is_anomaly" -eq 1 ]; then
            sensor=$(awk -F, -v ts="$ts" '$1==ts {print $2}' /app/sensor_data.csv)
            dist_rounded=$(printf "%.2f" "$dist")
            echo "$ts,$sensor,$dist_rounded" >> /app/ground_truth_anomalies.csv
        fi
    done
    rm -rf /tmp/frames

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
