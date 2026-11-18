#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os

os.makedirs('/home/user/backups', exist_ok=True)

log_content = \"\"\"[RECORD START]
File: blob_001.dat
Date: 2023-10-01
Status: SUCCESS
[RECORD END]
[RECORD START]
File: blob_002.dat
Date: 2023-10-01
Status: SUCCESS
[RECORD END]
[RECORD START]
File: blob_003.dat
Date: 2023-10-02
Status: FAILED
[RECORD END]
[RECORD START]
File: blob_004.dat
Date: 2023-10-02
Status: SUCCESS
[RECORD END]
[RECORD START]
File: blob_005.dat
Date: 2023-10-03
Status: SUCCESS
[RECORD END]
\"\"\"

with open('/home/user/backup.log', 'w') as f:
    f.write(log_content)

with open('/home/user/backups/blob_001.dat', 'wb') as f:
    f.write(b'BKP1_valid_data_for_file_1')

with open('/home/user/backups/blob_002.dat', 'wb') as f:
    f.write(b'ERR1_corrupted_data')

with open('/home/user/backups/blob_003.dat', 'wb') as f:
    f.write(b'BKP1_data_3')

with open('/home/user/backups/blob_004.dat', 'wb') as f:
    f.write(b'BKP1_valid_data_for_file_4')
"

    chmod -R 777 /home/user
