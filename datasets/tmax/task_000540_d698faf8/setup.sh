#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make file
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/processed_data

    cat << 'EOF' > /home/user/pipeline.conf
[Input]
Directory=/home/user/raw_data
Extension=.dat
MaxYear=2021
OriginalEncoding=WINDOWS-1252

[Output]
Directory=/home/user/processed_data
Prefix=dataset_chunk_
LinesPerChunk=15
TargetEncoding=UTF-8
EOF

    generate_file() {
        local file=$1
        local lines=$2
        local char=$3
        > temp.txt
        for i in $(seq 1 $lines); do
            echo "Line $i with special character: $char" >> temp.txt
        done
        iconv -f UTF-8 -t WINDOWS-1252 temp.txt > "$file"
        rm temp.txt
    }

    generate_file "/home/user/raw_data/alpha.dat" 20 "café"
    touch -d "2020-05-15 10:00:00" "/home/user/raw_data/alpha.dat"

    generate_file "/home/user/raw_data/beta.dat" 50 "niño"
    touch -d "2022-01-10 10:00:00" "/home/user/raw_data/beta.dat"

    generate_file "/home/user/raw_data/gamma.dat" 25 "façade"
    touch -d "2019-11-20 10:00:00" "/home/user/raw_data/gamma.dat"

    generate_file "/home/user/raw_data/delta.txt" 30 "naïve"
    touch -d "2018-05-15 10:00:00" "/home/user/raw_data/delta.txt"

    chmod -R 777 /home/user
