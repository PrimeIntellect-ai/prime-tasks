#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat gcc libcurl4-openssl-dev curl openssl make sudo
    pip3 install pytest

    mkdir -p /home/user/legacy_web
    echo "Hello Legacy" > /home/user/legacy_web/index.html

    echo '#!/bin/bash' > /start_service.sh
    echo 'cd /home/user/legacy_web && python3 -m http.server 8080 >/dev/null 2>&1 &' >> /start_service.sh
    chmod +x /start_service.sh
    echo "/start_service.sh" >> /etc/bash.bashrc

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    chmod -R 777 /home/user
