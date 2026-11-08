#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++
    pip3 install pytest

    mkdir -p /app/corpus/evil /app/corpus/clean

    # Generate CSV files
    cat << 'EOF' > /app/corpus/evil/deadlock1.csv
timestamp,tx_id,action,resource_id
1,T1,HOLD,R1
2,T2,HOLD,R2
3,T1,WAIT,R2
4,T2,WAIT,R1
EOF

    cat << 'EOF' > /app/corpus/evil/deadlock2.csv
timestamp,tx_id,action,resource_id
1,A,HOLD,X
2,B,HOLD,Y
3,C,HOLD,Z
4,A,WAIT,Y
5,B,WAIT,Z
6,C,WAIT,X
EOF

    cat << 'EOF' > /app/corpus/clean/safe1.csv
timestamp,tx_id,action,resource_id
1,T1,HOLD,R1
2,T2,WAIT,R1
3,T1,HOLD,R2
EOF

    cat << 'EOF' > /app/corpus/clean/safe2.csv
timestamp,tx_id,action,resource_id
1,A,HOLD,X
2,B,HOLD,Y
3,A,WAIT,Y
EOF

    # Generate video with exactly 45 red frames
    # 30 fps * 1.5 seconds = 45 frames
    cd /tmp
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=1 -r 30 black1.mp4
    ffmpeg -f lavfi -i color=c=red:s=320x240:d=1.5 -r 30 red.mp4
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=1 -r 30 black2.mp4
    echo "file 'black1.mp4'" > list.txt
    echo "file 'red.mp4'" >> list.txt
    echo "file 'black2.mp4'" >> list.txt
    ffmpeg -f concat -i list.txt -c copy /app/dashboard_recording.mp4
    rm -f black1.mp4 red.mp4 black2.mp4 list.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
