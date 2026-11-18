#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
item_id,publish_date,raw_text
1,2023-01-15,"Hello, World! Great item."
2,2023/02/10,"Bad date format, should be dropped."
A3,2023-03-01,"Bad ID, should be dropped."
4,2023-04-20,"Testing... 1, 2, 3! Pipeline reproducibility."
5,2023-05-05,"Just letters and spaces"
6,2023-06-12,"   Extra   Spaces   Everywhere   "
EOF

    chmod -R 777 /home/user
