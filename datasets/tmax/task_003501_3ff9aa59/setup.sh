#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    # Create the correct configuration file
    cat << 'EOF' > /home/user/config.env
START_VAL=1000
STEP_SIZE=1000000000000000000
EOF

    # Create the broken default configuration file
    cat << 'EOF' > /home/user/.default_config.env
START_VAL=1000
STEP_SIZE=8000000000000000000
EOF

    # Create the faulty datagen script
    cat << 'EOF' > /home/user/datagen.sh
#!/bin/bash
source "${CONFIG_PATH:-/home/user/.default_config.env}"

TARGET_MAX=9000000000000000000
CURRENT=$START_VAL

> /home/user/sequence.log

while [ "$CURRENT" -lt "$TARGET_MAX" ]; do
    echo "$CURRENT" >> /home/user/sequence.log
    CURRENT=$(( CURRENT + STEP_SIZE ))
done
echo "Done"
EOF

    chmod +x /home/user/datagen.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
