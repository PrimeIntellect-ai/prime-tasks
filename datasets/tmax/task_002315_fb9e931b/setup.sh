#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gcc
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/docs

    # Generate audio instructions
    espeak -w /app/instructions.wav "Please split the file introduction.txt into chunks of exactly one thousand bytes each. Name the chunks intro_part1.txt, intro_part2.txt, and so on. Also, merge setup.txt and usage.txt in that order into a new file called guide.txt."

    # Create text files with exact sizes
    yes "A" | head -c 2500 > /home/user/docs/introduction.txt
    yes "B" | head -c 800 > /home/user/docs/setup.txt
    yes "C" | head -c 1200 > /home/user/docs/usage.txt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
