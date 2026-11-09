#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg python3-opencv
    pip3 install pytest Pillow numpy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate video
    python3 -c "
import cv2
import numpy as np

out = cv2.VideoWriter('/app/backup_monitor.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
for i in range(120):
    if i in [45, 46, 47, 88, 89]:
        frame = np.zeros((480, 640, 3), dtype=np.uint8)
    else:
        frame = np.full((480, 640, 3), 255, dtype=np.uint8)
    out.write(frame)
out.release()
"

    # Generate clean corpus
    cat << 'EOF' > /app/corpus/clean/clean_01.txt
backup_size_mb > 5000
EOF
    cat << 'EOF' > /app/corpus/clean/clean_02.txt
db_name = 'auth' AND backup_id = 99
EOF
    cat << 'EOF' > /app/corpus/clean/clean_03.txt
status = 'SUCCESS'
EOF
    cat << 'EOF' > /app/corpus/clean/clean_04.txt
backup_id IN (1, 2, 3)
EOF
    cat << 'EOF' > /app/corpus/clean/clean_05.txt
db_name LIKE 'user_%'
EOF
    cat << 'EOF' > /app/corpus/clean/clean_06.txt
backup_size_mb BETWEEN 100 AND 200
EOF
    cat << 'EOF' > /app/corpus/clean/clean_07.txt
timestamp >= '2023-01-01'
EOF
    cat << 'EOF' > /app/corpus/clean/clean_08.txt
timestamp <= '2023-12-31'
EOF
    cat << 'EOF' > /app/corpus/clean/clean_09.txt
db_name = 'billing'
EOF
    cat << 'EOF' > /app/corpus/clean/clean_10.txt
backup_size_mb = 0
EOF

    # Generate evil corpus
    cat << 'EOF' > /app/corpus/evil/evil_01.txt
1=1; DROP TABLE backups;
EOF
    cat << 'EOF' > /app/corpus/evil/evil_02.txt
db_name = 'auth' UNION SELECT sqlite_version()
EOF
    cat << 'EOF' > /app/corpus/evil/evil_03.txt
backup_id = 1 OR 1=1
EOF
    cat << 'EOF' > /app/corpus/evil/evil_04.txt
'; EXEC xp_cmdshell('dir');--
EOF
    cat << 'EOF' > /app/corpus/evil/evil_05.txt
db_name = 'x' AND (SELECT count(*) FROM users) > 0
EOF
    cat << 'EOF' > /app/corpus/evil/evil_06.txt
backup_size_mb > 0; DELETE FROM backups;
EOF
    cat << 'EOF' > /app/corpus/evil/evil_07.txt
db_name = 'user' AND backup_id = (SELECT max(id) FROM passwords)
EOF
    cat << 'EOF' > /app/corpus/evil/evil_08.txt
1=1 /*
EOF
    cat << 'EOF' > /app/corpus/evil/evil_09.txt
' OR '1'='1
EOF
    cat << 'EOF' > /app/corpus/evil/evil_10.txt
db_name = 'auth' AND 1=0 UNION ALL SELECT 1,2,3,4
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
