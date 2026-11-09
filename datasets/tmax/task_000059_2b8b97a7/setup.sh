#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg bc
    pip3 install pytest

    mkdir -p /app/data /app/corpora/clean /app/corpora/evil

    # Create a 4-second video at 30 fps -> 120 frames
    ffmpeg -f lavfi -i testsrc=duration=4:size=320x240:rate=30 -c:v libx264 /app/data/conveyor.mp4

    # Use bash to evaluate brace expansion correctly
    bash -c '
    # Generate 5 clean files
    for i in {1..5}; do
        f="/app/corpora/clean/clean_$i.csv"
        echo "frame,timestamp_sec,event_code" > "$f"
        for j in {1..120}; do
            ts=$(echo "scale=3; $j * 0.033" | bc)
            hex=$(printf "0x%04X" $RANDOM)
            echo "$j,$ts,$hex" >> "$f"
        done
    done

    # Generate 5 evil files
    # Evil 1: Wrong row count (119 frames)
    f="/app/corpora/evil/evil_1.csv"
    echo "frame,timestamp_sec,event_code" > "$f"
    for j in {1..119}; do
        ts=$(echo "scale=3; $j * 0.033" | bc)
        hex=$(printf "0x%04X" $RANDOM)
        echo "$j,$ts,$hex" >> "$f"
    done

    # Evil 2: Bad header
    f="/app/corpora/evil/evil_2.csv"
    echo "frame_num,timestamp,event" > "$f"
    for j in {1..120}; do
        ts=$(echo "scale=3; $j * 0.033" | bc)
        hex=$(printf "0x%04X" $RANDOM)
        echo "$j,$ts,$hex" >> "$f"
    done

    # Evil 3: Non-sequential frames
    f="/app/corpora/evil/evil_3.csv"
    echo "frame,timestamp_sec,event_code" > "$f"
    for j in {1..120}; do
        frame=$j
        if [ $j -eq 50 ]; then frame=49; fi
        ts=$(echo "scale=3; $j * 0.033" | bc)
        hex=$(printf "0x%04X" $RANDOM)
        echo "$frame,$ts,$hex" >> "$f"
    done

    # Evil 4: Non-monotonic timestamps
    f="/app/corpora/evil/evil_4.csv"
    echo "frame,timestamp_sec,event_code" > "$f"
    for j in {1..120}; do
        ts=$(echo "scale=3; $j * 0.033" | bc)
        if [ $j -eq 60 ]; then ts="0.000"; fi
        hex=$(printf "0x%04X" $RANDOM)
        echo "$j,$ts,$hex" >> "$f"
    done

    # Evil 5: Invalid hex
    f="/app/corpora/evil/evil_5.csv"
    echo "frame,timestamp_sec,event_code" > "$f"
    for j in {1..120}; do
        ts=$(echo "scale=3; $j * 0.033" | bc)
        hex=$(printf "0x%04X" $RANDOM)
        if [ $j -eq 100 ]; then hex="0x123g"; fi
        echo "$j,$ts,$hex" >> "$f"
    done
    '

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
