#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install necessary packages for the task
    apt-get install -y imagemagick tesseract-ocr fonts-dejavu-core g++

    # Create directories
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create clean datasets
    for i in $(seq 1 5); do
      cat <<EOF > /app/corpus/clean/data_${i}.csv
1.0, 5.0, 10.0
2.0, 6.0, 20.0
3.0, 7.0, 30.0
4.0, 8.0, 40.0
5.0, 9.0, 50.0
EOF
    done

    # Create evil datasets
    for i in $(seq 1 5); do
      cat <<EOF > /app/corpus/evil/data_${i}.csv
1.0, 5.0, 10.5
2.0, 6.0, 20.0
3.0, 7.0, 30.5
4.0, 8.0, 40.0
5.0, 9.0, 50.5
EOF
    done

    # Generate the image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
    -draw "text 10,30 'BOOTSTRAP_ITERS=500'" \
    -draw "text 10,60 'PRIOR_ALPHA=1'" \
    -draw "text 10,90 'PRIOR_BETA=50'" \
    -draw "text 10,120 'POSTERIOR_THRESHOLD=0.03'" \
    /app/config.png

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
