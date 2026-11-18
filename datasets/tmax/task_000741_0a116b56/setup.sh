#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/instructions.wav "To generate the backup, first prepend the exact magic header string B K U P 2 0 2 4 to the data. Then, process the original data bytes. For any byte that represents a standard lowercase ASCII letter, shift its value up by one. For example, a becomes b, and z becomes left curly brace. Leave all other bytes completely unchanged. Finally, compress the entire combined payload, including the header, using the standard L Z M A algorithm."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
