#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak g++ ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    espeak "The secret hacker user ID is eight four two six." -w /app/intercept.wav

    for i in {1..10}; do
        echo "event_id,timestamp,user_id,status,payload\n1,1620000000,1001,OK,data\n2,1620000005,1002,WARN,data" > /app/corpus/clean/clean_$i.csv
    done

    echo "event_id,timestamp,user_id,status,payload\n1,1620000000,8426,OK,data" > /app/corpus/evil/evil_1.csv
    echo "event_id,timestamp,user_id,status,payload\n1,-500,1001,OK,data" > /app/corpus/evil/evil_2.csv
    echo "event_id,timestamp,user_id,status,payload\n1,1620000000,1001,FAIL,data" > /app/corpus/evil/evil_3.csv
    echo "event_id,timestamp,user_id,status,payload\n1,abc,1001,OK,data" > /app/corpus/evil/evil_4.csv

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
