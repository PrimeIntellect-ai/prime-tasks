#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak gcc make libmicrohttpd-dev curl
    pip3 install pytest

    mkdir -p /app

    TEXT="Transaction from account 101 to account 102 with amount 500. Transaction from account 102 to account 103 with amount 300. Transaction from account 103 to account 101 with amount 200. Transaction from account 101 to account 104 with amount 1000. Transaction from account 104 to account 105 with amount 400. Transaction from account 105 to account 106 with amount 50. Transaction from account 106 to account 104 with amount 10."

    espeak -w /app/audit_intercept.wav "$TEXT"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
