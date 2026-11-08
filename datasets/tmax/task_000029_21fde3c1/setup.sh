#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak-ng ffmpeg bc
    pip3 install pytest

    mkdir -p /app/corpus/evil /app/corpus/clean

    # Clean corpus
    echo "5 + 2" > /app/corpus/clean/clean1.txt
    echo "( 10 * 3 ) / 2" > /app/corpus/clean/clean2.txt
    echo "100 - ( 55 + 5 )" > /app/corpus/clean/clean3.txt
    echo "1" > /app/corpus/clean/clean4.txt

    # Evil corpus
    echo "5 + + 2" > /app/corpus/evil/evil1.txt
    echo "( 5 + 2" > /app/corpus/evil/evil2.txt
    echo "5 + 2 ; ls" > /app/corpus/evil/evil3.txt
    echo "5 + 2 )" > /app/corpus/evil/evil4.txt
    echo "\$(whoami)" > /app/corpus/evil/evil5.txt
    echo "\`id\`" > /app/corpus/evil/evil6.txt

    # Audio file generation
    espeak-ng -w /app/qa_instructions.wav "The required environment variable is QA_TEST_SEED and its value must be 8472."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
