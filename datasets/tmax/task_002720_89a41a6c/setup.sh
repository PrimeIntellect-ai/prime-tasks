#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg jq util-linux gawk
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate a test video
    ffmpeg -f lavfi -i testsrc=duration=20:size=640x480:rate=30 -pix_fmt yuv420p /app/screencast.mp4

    # Extract the reference frame for building the clean corpus
    ffmpeg -ss 00:00:10 -i /app/screencast.mp4 -frames:v 1 /tmp/ref.jpg

    cd /tmp
    echo "type,value" > metadata.csv
    echo "reference,true" >> metadata.csv
    cp /tmp/ref.jpg frame.jpg

    sha256_csv=$(sha256sum metadata.csv | awk '{print $1}')
    sha256_jpg=$(sha256sum frame.jpg | awk '{print $1}')

    cat <<EOF > manifest.json
{
  "metadata.csv": "$sha256_csv",
  "frame.jpg": "$sha256_jpg"
}
EOF

    # Clean corpus
    tar -czf /app/corpus/clean/clean_1.tar.gz manifest.json metadata.csv frame.jpg

    # Evil 1: Valid structure, but lock file will be an issue
    cp /app/corpus/clean/clean_1.tar.gz /app/corpus/evil/evil_1.tar.gz

    # Evil 2: Invalid manifest.json
    echo "invalid json" > manifest.json
    tar -czf /app/corpus/evil/evil_2.tar.gz manifest.json metadata.csv frame.jpg

    # Evil 3: Mismatched checksum
    cat <<EOF > manifest.json
{
  "metadata.csv": "1111111111111111111111111111111111111111111111111111111111111111",
  "frame.jpg": "$sha256_jpg"
}
EOF
    tar -czf /app/corpus/evil/evil_3.tar.gz manifest.json metadata.csv frame.jpg

    # Evil 4: Path traversal
    cat <<EOF > manifest.json
{
  "../etc/passwd": "abc",
  "frame.jpg": "$sha256_jpg"
}
EOF
    tar -czf /app/corpus/evil/evil_4.tar.gz manifest.json metadata.csv frame.jpg

    # Evil 5: Wrong reference frame
    echo "bad image data" > frame.jpg
    sha256_bad=$(sha256sum frame.jpg | awk '{print $1}')
    cat <<EOF > manifest.json
{
  "metadata.csv": "$sha256_csv",
  "frame.jpg": "$sha256_bad"
}
EOF
    tar -czf /app/corpus/evil/evil_5.tar.gz manifest.json metadata.csv frame.jpg

    # Evil 6: Not a valid tar.gz
    echo "not a tar" > /app/corpus/evil/evil_6.tar.gz

    # Cleanup tmp
    rm -f /tmp/ref.jpg /tmp/frame.jpg /tmp/metadata.csv /tmp/manifest.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
