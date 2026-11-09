#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak build-essential curl wget ffmpeg
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/lab_log_12.wav "Observation one. Variable alpha is 1.0, variable beta is 2.1. Observation two. Variable alpha is 2.0, variable beta is 3.9. Observation three. Variable alpha is 3.0, variable beta is 6.2. Observation four. Variable alpha is 4.0, variable beta is 8.0. Observation five. Variable alpha is invalid, variable beta is 10.1. Observation six. Variable alpha is 5.0, variable beta is 9.9. Observation seven. Variable alpha is 6.0, variable beta is 12.1."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
