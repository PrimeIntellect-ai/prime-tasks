#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest
    apt-get install -y file tar gzip

    mkdir -p /home/user/research_data/subdir1
    mkdir -p /home/user/research_data/subdir2
    mkdir -p /home/user/recovered_pngs
    mkdir -p /home/user/clean_csvs

    # 1. Create Symlink Loop
    ln -s /home/user/research_data /home/user/research_data/infinite_loop

    # 2. Create PNGs hidden as .dat
    python3 -c '
with open("/home/user/research_data/image1.dat", "wb") as f:
    f.write(b"\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52")
with open("/home/user/research_data/subdir1/image2.dat", "wb") as f:
    f.write(b"\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52")
'
    echo "This is not a PNG" > /home/user/research_data/subdir2/data.dat

    # 3. Create CSVs (WINDOWS-1252 encoded)
    echo "id,name" | iconv -f UTF-8 -t WINDOWS-1252 > /home/user/research_data/recent1.csv
    echo "1,René" | iconv -f UTF-8 -t WINDOWS-1252 >> /home/user/research_data/recent1.csv
    echo "id,name" | iconv -f UTF-8 -t WINDOWS-1252 > /home/user/research_data/old.csv
    echo "2,José" | iconv -f UTF-8 -t WINDOWS-1252 >> /home/user/research_data/old.csv
    touch -d "10 days ago" /home/user/research_data/old.csv

    # 4. Create Archives
    mkdir -p /tmp/dummy
    echo "hello" > /tmp/dummy/test.txt
    tar -czf /home/user/research_data/good.tar.gz -C /tmp dummy/test.txt
    echo "corrupt data" > /home/user/research_data/bad1.tar.gz
    echo "more corrupt data" > /home/user/research_data/subdir1/bad2.tar.gz

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/research_data
    chown -R user:user /home/user/recovered_pngs
    chown -R user:user /home/user/clean_csvs
    chmod -R 777 /home/user
