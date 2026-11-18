#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    printf "System report 1: Error occurred at connection \xA9 - requires immediate attention. Padding out the file so it is safely over 50 bytes long." > /home/user/data/report1.log
    printf "System report 2: The network interface \xE6 failed to initialize properly. Padding out the file so it is safely over 50 bytes long." > /home/user/data/report2.log
    printf "Too short \xA9." > /home/user/data/tiny.log
    printf "Not a log file. Not a log file. Not a log file. Not a log file." > /home/user/data/ignore.txt

    chmod -R 777 /home/user
