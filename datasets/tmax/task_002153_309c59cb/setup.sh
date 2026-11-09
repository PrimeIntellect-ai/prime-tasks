#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_metrics.csv
1672531200,es-ES,ui.button.save,15
1672531260,es-ES,ui.button.save,
1672531320,es-ES,ui.button.save,20
1672531200,fr-FR,ui.button.cancel,
1672531260,fr-FR,ui.button.cancel,5
1672531320,fr-FR,ui.button.cancel,
1672531200,es-ES,ui.menu.file,10
1672531260,es-ES,ui.menu.file,
1672531320,es-ES,ui.button.save,
EOF

    chmod -R 777 /home/user
