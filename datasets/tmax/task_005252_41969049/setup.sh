#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
id,age,review
123e4567-e89b-12d3-a456-426614174000,25,Great product, highly recommend.
invalid-id,30,Bad.
123e4567-e89b-12d3-a456-426614174001,notanage,Okay I guess
123e4567-e89b-12d3-a456-426614174002,17,Too young.
123e4567-e89b-12d3-a456-426614174003,65,Works well. Very sturdy.
123e4567-e89b-12d3-a456-426614174004,45,Awful, terrible.
123e4567-e89b-12d3-a456-426614174005,101,Too old
123e4567-e89b-12d3-a456-426614174006,30,   Lots   of   spaces.  
EOF

    chmod -R 777 /home/user
