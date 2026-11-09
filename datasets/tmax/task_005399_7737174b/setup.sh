#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install necessary packages for the task
    apt-get install -y ffmpeg fonts-dejavu-core openssh-client gcc build-essential

    # Create directories
    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate video with the partial PIN at 3 seconds
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=5 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='SSH PIN\: 74??':x=(w-text_w)/2:y=(h-text_h)/2:fontsize=48:fontcolor=white:enable='between(t,3,4)'" -c:v libx264 -y /app/server_room.mp4

    # Generate SSH key with the exact PIN
    ssh-keygen -t rsa -b 2048 -N "7482" -f /app/backup_id_rsa -q

    # Populate evil corpus
    echo -n "../../../etc/passwd" > /app/corpus/evil/1.txt
    echo -n "..%2f..%2f..%2fetc%2fpasswd" > /app/corpus/evil/2.txt
    echo -n "..%5cwindows%5csystem32" > /app/corpus/evil/3.txt
    echo -n "image.png%00.php" > /app/corpus/evil/4.txt
    echo -n "folder/..%2f" > /app/corpus/evil/5.txt
    echo -n "....//" > /app/corpus/evil/6.txt

    # Populate clean corpus
    echo -n "monthly_report_2023.pdf" > /app/corpus/clean/1.txt
    echo -n "images/profile.jpg" > /app/corpus/clean/2.txt
    echo -n "archive.tar.gz" > /app/corpus/clean/3.txt
    echo -n ".hidden_file" > /app/corpus/clean/4.txt
    echo -n "document..txt" > /app/corpus/clean/5.txt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
