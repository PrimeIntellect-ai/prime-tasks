#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6
    pip3 install pytest pandas numpy opencv-python

    mkdir -p /app/clean_corpus
    mkdir -p /app/evil_corpus

    # Create a test video
    ffmpeg -f lavfi -i testsrc=duration=1:size=64x64:rate=10 -c:v libx264 /app/experiment_record.mp4

    # Create clean corpus
    cat << 'EOF' > /app/clean_corpus/clean1.csv
frame_id,intensity,event_flag
0,128.5,False
1,255.0,True
EOF

    cat << 'EOF' > /app/clean_corpus/clean2.csv
frame_id,intensity,event_flag
10,0.0,False
EOF

    # Create evil corpus
    cat << 'EOF' > /app/evil_corpus/evil1.csv
frame_id,intensity,event_flag
-1,128.5,False
EOF

    cat << 'EOF' > /app/evil_corpus/evil2.csv
frame_id,intensity,event_flag
0,256.0,False
EOF

    cat << 'EOF' > /app/evil_corpus/evil3.csv
frame_id,intensity,event_flag
0,128.5,TRUE
EOF

    cat << 'EOF' > /app/evil_corpus/evil4.csv
frame_id,intensity,event_flag
0,128.5,False
1,255.1,False
EOF

    cat << 'EOF' > /app/evil_corpus/evil5.csv
frame_id,intensity,event_flag
0,128.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
