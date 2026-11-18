#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak-ng ffmpeg
    pip3 install pytest

    mkdir -p /app
    espeak-ng -w /app/attacker_memo.wav "the payload was delivered via open redirect on our login page the target domain was secure dash update dot net and the exfiltration ip is one nine two dot one six eight dot one five dot seven"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
