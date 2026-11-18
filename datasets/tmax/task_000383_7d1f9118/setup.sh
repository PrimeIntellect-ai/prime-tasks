#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar gawk sed espeak ffmpeg curl socat netcat
    pip3 install pytest

    mkdir -p /app
    mkdir -p /tmp/docs

    # Create text files with different encodings
    echo "[[TITLE:System Specs]]\nHere are the [[BOLD:details]]..." | iconv -f UTF-8 -t ISO-8859-1 > /tmp/docs/specs.txt
    echo "[[TITLE:Introduction]]\nWelcome to the [[BOLD:legacy]] system." | iconv -f UTF-8 -t UTF-16LE > /tmp/docs/intro.txt

    # Zip and Tar
    cd /tmp
    zip -r internal_files.zip docs/
    tar -czf legacy_docs.tar.gz internal_files.zip

    # Split into .001, .002, etc. Ensure at least two parts.
    split -b 250 -d -a 3 legacy_docs.tar.gz parts_

    # Rename to start from 001
    count=1
    for f in parts_*; do
        num=$(printf "%03d" $count)
        mv "$f" "/app/legacy_docs.tar.gz.$num"
        count=$((count + 1))
    done

    # Generate audio memo
    espeak -w /app/writer_notes.wav "Hello, please serve the finalized documentation index on port eight zero eight zero. Ensure all incoming requests contain the bearer token 'DocAuth992'. Finally, remember to append the exact phrase 'Drafted by TechWriter Pro' at the end of every parsed document."

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
