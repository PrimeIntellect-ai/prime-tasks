#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data_volume
    mkdir -p /home/user/archive_links

    cat << 'EOF' > /home/user/storage_conf.ini
[Paths]
TargetDir = /home/user/data_volume
LogFile = /home/user/app_logs.txt
ArchiveLinksDir = /home/user/archive_links

[Settings]
Deduplicate = True
CreateArchiveLinks = True
EOF

    echo -n "AAAAAAAAAA" > /home/user/data_volume/f1.dat
    echo -n "AAAAAAAAAA" > /home/user/data_volume/f2.dat
    echo -n "BBBBBBBBBB" > /home/user/data_volume/f3.dat
    echo -n "BBBBBBBBBB" > /home/user/data_volume/f4.dat
    echo -n "CCCCC" > /home/user/data_volume/f5.dat

    cat << 'EOF' > /home/user/app_logs.txt
[2023-10-01 10:00:00] INFO - Job Start
Job ID: 101
File: /home/user/data_volume/f1.dat
Status: ACTIVE

[2023-10-01 10:05:00] INFO - Job Start
Job ID: 102
File: /home/user/data_volume/f2.dat
Status: INACTIVE

[2023-10-01 10:10:00] INFO - Job Start
Job ID: 103
File: /home/user/data_volume/f3.dat
Status: ACTIVE

[2023-10-01 10:15:00] INFO - Job Start
Job ID: 104
File: /home/user/data_volume/f4.dat
Status: ACTIVE

[2023-10-01 10:20:00] INFO - Job Start
Job ID: 105
File: /home/user/data_volume/f5.dat
Status: INACTIVE

[2023-10-01 10:25:00] INFO - Job Start
Job ID: 106
File: /home/user/data_volume/f1.dat
Status: INACTIVE
EOF

    chown -R user:user /home/user/data_volume /home/user/archive_links /home/user/storage_conf.ini /home/user/app_logs.txt

    chmod -R 777 /home/user
