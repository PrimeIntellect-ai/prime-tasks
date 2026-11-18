#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/subs_raw.log
[00:00:00] [NARRATOR] Hello, world. We begin now.
[00:00:03] [NARRATOR] Welcome to the tutorial!
[00:00:09] [GUEST] This is exciting, right?
[00:00:11] [GUEST] I am ready.
[00:00:17] [NARRATOR] Let us proceed.
EOF

    cat << 'EOF' > /home/user/dict.csv
hello,hola
world,mundo
tutorial,lección
exciting,emocionante
ready,listo
proceed,continuar
EOF

    chmod -R 777 /home/user
