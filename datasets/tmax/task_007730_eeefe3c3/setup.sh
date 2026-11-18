#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk tar gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data/dir1
    mkdir -p /home/user/raw_data/dir2

    # Create file_A.txt (>50KB, approx 60KB, 800 lines)
    awk 'BEGIN { for(i=1;i<=800;i++) printf "Data line %05d padding padding padding padding padding padding padding padding padding padding padding padding padding padding\n", i }' > /home/user/raw_data/dir1/file_A.txt

    # Create file_B.txt (<50KB, approx 10KB, 100 lines)
    awk 'BEGIN { for(i=1;i<=100;i++) printf "Small line %05d padding padding padding padding padding padding padding padding padding padding padding padding padding\n", i }' > /home/user/raw_data/dir2/file_B.txt

    # Create file_C.txt (>50KB, approx 80KB, 1200 lines)
    awk 'BEGIN { for(i=1;i<=1200;i++) printf "Record %05d padding padding padding padding padding padding padding padding padding padding padding padding padding padding\n", i }' > /home/user/raw_data/dir2/file_C.txt

    # Create file_D.csv (>50KB, different extension)
    awk 'BEGIN { for(i=1;i<=1000;i++) printf "CSV,%05d,padding,padding,padding,padding,padding,padding,padding,padding,padding,padding,padding,padding,padding,padding\n", i }' > /home/user/raw_data/file_D.csv

    # Create archive
    cd /home/user/raw_data
    tar -czf /home/user/raw_research_data.tar.gz .
    cd /home/user
    rm -rf /home/user/raw_data

    chmod -R 777 /home/user
