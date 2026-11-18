#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/locales

    cat << 'EOF' > /home/user/locales/base.csv
ERR_100,en,Error 100
ERR_100,es,Error 100 en espanol
ERR_200,en,Error 200
SYS_001,en,System start
ERR_404,en,Not found
ERR_404,fr,Introuvable
ERR_9999,en,Too many digits
EOF

    cat << 'EOF' > /home/user/locales/update.csv
ERR_100,es,Error 100 actualizado
ERR_200,fr,Erreur 200
ERR_500,en,Server error
SYS_002,en,System stop
EOF

    chown -R user:user /home/user/locales
    chmod -R 777 /home/user
