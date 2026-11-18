#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-openbsd gawk coreutils sed
    pip3 install pytest

    # Create directories
    mkdir -p /app /opt/oracle

    # Create dummy scripts to satisfy initial state tests
    # (These will be overwritten by the verifier framework)
    echo "#!/bin/bash" > /app/start_services.sh
    chmod +x /app/start_services.sh

    echo "#!/bin/bash" > /opt/oracle/aggregator_oracle.sh
    chmod +x /opt/oracle/aggregator_oracle.sh

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
