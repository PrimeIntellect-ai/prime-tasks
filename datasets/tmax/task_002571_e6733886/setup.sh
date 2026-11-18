#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick gcc coreutils sed
    pip3 install pytest

    # Create setup script to use bash features (arrays, brace expansion)
    cat << 'EOF' > /tmp/setup.sh
#!/bin/bash
mkdir -p /app/evil /app/clean

# Generate the 20 frames
colors=("red" "blue" "yellow" "green" "blue" "red" "yellow" "green" "blue" "yellow" "red" "green" "blue" "red" "yellow" "green" "blue" "yellow" "red" "blue")
for i in "${!colors[@]}"; do
    # Create 1 second video segment for each color
    ffmpeg -f lavfi -i color=c=${colors[$i]}:s=320x240:r=1 -t 1 -c:v libx264 -preset ultrafast /tmp/frame_$i.mp4 -y
done

# Concatenate them
> /tmp/files.txt
for i in {0..19}; do
    echo "file '/tmp/frame_$i.mp4'" >> /tmp/files.txt
done
ffmpeg -f concat -safe 0 -i /tmp/files.txt -c copy /app/primer_synthesis.mp4

# Generate Clean Corpus (Random DNA)
for i in {1..50}; do
    tr -dc 'ACGT' < /dev/urandom | head -c 100000 > /app/clean/clean_$i.txt
done

# Generate Evil Corpus (Random DNA + Mutated Primer)
# Primer: AGTCGATCGTACGATCGTAG
for i in {1..50}; do
    # Generate background
    tr -dc 'ACGT' < /dev/urandom | head -c 100000 > /tmp/evil_bg.txt

    # Mutate primer slightly (0 to 3 mismatches)
    if [ $((i % 2)) -eq 0 ]; then
        primer="AGTCGATCGTACGATCGTCC"
    else
        primer="AGTCGATCGTACGATCGTAG"
    fi

    # Inject into a random position (middle)
    sed -i "s/^\(.\{50000\}\).\{20\}/\1${primer}/" /tmp/evil_bg.txt
    mv /tmp/evil_bg.txt /app/evil/evil_$i.txt
done
EOF

    bash /tmp/setup.sh
    rm -f /tmp/setup.sh /tmp/frame_*.mp4 /tmp/files.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
