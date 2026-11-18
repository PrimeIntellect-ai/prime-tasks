#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the dummy executable for context
    mkdir -p /app
    echo -e '#!/bin/bash\nexit 0' > /app/evasion_sim
    chmod +x /app/evasion_sim

    # Create user and required directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/certs

    # Ensure permissions are correct
    chmod -R 777 /home/user
    chmod -R 777 /app
