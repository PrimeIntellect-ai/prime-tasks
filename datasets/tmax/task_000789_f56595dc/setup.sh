#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip multimon-ng sox libsox-fmt-all socat netcat-openbsd curl
    pip3 install pytest

    mkdir -p /app
    sox -n -r 8000 /app/sequence_signal.wav synth 0.2 sin 697 sin 1209 delay 0 0 \
    synth 0.2 sin 697 sin 1336 delay 0.3 0.3 \
    synth 0.2 sin 770 sin 1209 delay 0.6 0.6 \
    synth 0.2 sin 697 sin 1477 delay 0.9 0.9 \
    synth 0.2 sin 697 sin 1209 delay 1.2 1.2 \
    synth 0.2 sin 697 sin 1336 delay 1.5 1.5 \
    synth 0.2 sin 770 sin 1209 delay 1.8 1.8 \
    synth 0.2 sin 697 sin 1209 delay 2.1 2.1 remix -

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
