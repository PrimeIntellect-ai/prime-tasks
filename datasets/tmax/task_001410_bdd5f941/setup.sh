#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required tools
    apt-get install -y ffmpeg g++ make python3-matplotlib wget

    # Create directories
    mkdir -p /app/vendor
    mkdir -p /app/oracle
    mkdir -p /home/user/src
    mkdir -p /home/user/bin

    # Create dummy video file
    ffmpeg -f lavfi -i color=c=black:s=16x16:d=10 -r 30 -pix_fmt yuv420p /app/fluorescence_sensor_run01.mp4

    # Create basis file
    echo "1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0" > /app/nucleotide_basis.csv
    echo "0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0" >> /app/nucleotide_basis.csv
    echo "0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0" >> /app/nucleotide_basis.csv
    echo "0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0" >> /app/nucleotide_basis.csv

    # Download stb_image.h
    wget -qO /app/vendor/stb_image.h https://raw.githubusercontent.com/nothings/stb/master/stb_image.h

    # Create dummy oracle executable
    echo '#!/bin/bash' > /app/oracle/seq_extractor_ref
    echo 'echo "ATCG"' >> /app/oracle/seq_extractor_ref
    chmod +x /app/oracle/seq_extractor_ref

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
