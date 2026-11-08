#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ticket_1029/data

    # Generate 100 files
    for i in $(seq -w 1 100); do
        filename="/home/user/ticket_1029/data/file_${i}.csv"
        # 10 lines per file, cost is exactly 10.50
        for j in $(seq 1 10); do
            echo "srv_${i}_${j},2023-10-01T12:00:00,0.75,10.50" >> "$filename"
        done
    done

    # Corrupt file 1: file_037.csv (Massive negative outlier)
    # Replace the 5th line's cost
    sed -i '5s/.*/srv_037_5,2023-10-01T12:00:00,0.75,-99999999.99/' /home/user/ticket_1029/data/file_037.csv

    # Corrupt file 2: file_082.csv (Malformed string)
    # Replace the 8th line's cost
    sed -i '8s/.*/srv_082_8,2023-10-01T12:00:00,0.75,ERR_TIMEOUT/' /home/user/ticket_1029/data/file_082.csv

    chown -R user:user /home/user/ticket_1029
    chmod -R 777 /home/user
