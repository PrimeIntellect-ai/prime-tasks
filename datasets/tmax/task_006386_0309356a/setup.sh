#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/loc_raw.txt
Starting export...
[2023-11-01 09:14:22] {es-ES} <GREETING> : "Hola\u0020Mundo"
DEBUG: Connection established.
[2023-11-01 09:14:23] {fr-FR} <FAREWELL> : "Au\u0020revoir"
[2023-11-01 09:14:24] {es-ES} <FAREWELL> : "Adi\u00F3s"
[2023-11-01 09:14:25] {de-DE} <GREETING> : "Hallo\u0020Welt"
WARN: Retry limit reached.
[2023-11-01 09:14:26] {fr-FR} <GREETING> : "Bonjour\u0020le\u0020monde"
[2023-11-01 09:14:27] {de-DE} <FAREWELL> : "Auf\u0020Wiedersehen"
[2023-11-01 09:14:28] {jp-JP} <GREETING> : "\u3053\u3093\u306B\u3061\u306F"
Export finished.
EOF

    mkdir -p /home/user/loc_processor

    chmod -R 777 /home/user
