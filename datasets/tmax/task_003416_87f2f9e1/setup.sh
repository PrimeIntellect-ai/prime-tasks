#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest opencv-python-headless numpy

    # Generate the video
    mkdir -p /app
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=120:r=1 -vf "drawbox=x=0:y=0:w=10:h=10:color=red:t=fill:enable='between(t,15,20)+between(t,85,90)'" -c:v libx264 -y /app/dashboard.mp4

    # Generate Adversarial Corpora
    mkdir -p /app/verifier/clean_logs
    mkdir -p /app/verifier/evil_logs

    # CLEAN LOGS: Valid timings, no attack windows, pure Unicode scripts
    cat << 'EOF' > /app/verifier/clean_logs/log1.log
1710000030000 | userA | Normal message in English
1710000031000 | userA | Еще одно сообщение
1710000032500 | userA | Checking status
1710000033100 | userA | Heartbeat
1710000034600 | userA | OK
EOF

    # EVIL LOGS: Attack window match
    cat << 'EOF' > /app/verifier/evil_logs/evil1.log
1710000015500 | userB | This is an attack
1710000088000 | userC | Another attack
EOF

    # EVIL LOGS: Rolling stddev < 100ms
    # Interarrival times: 1000, 1000, 1000, 1000 (stddev = 0.0)
    cat << 'EOF' > /app/verifier/evil_logs/evil2.log
1710000040000 | bot1 | Init
1710000041000 | bot1 | Step 1
1710000042000 | bot1 | Step 2
1710000043000 | bot1 | Step 3
1710000044000 | bot1 | This line should be dropped because stddev of diffs is 0
EOF

    # EVIL LOGS: Unicode mix
    cat << 'EOF' > /app/verifier/evil_logs/evil3.log
1710000060000 | userD | Paypаl login attempt
1710000061000 | userE | admіn access
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
