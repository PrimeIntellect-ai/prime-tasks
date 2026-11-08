#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git espeak-ng coreutils sed
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/telemetry-processor/bin

    # 1. Create coredump
    head -c 1024 /dev/urandom > /app/coredump.dat
    echo "CFG-X9B2K1L7" >> /app/coredump.dat
    head -c 1024 /dev/urandom >> /app/coredump.dat

    # 2. Create audio file
    espeak-ng -w /app/telemetry.wav "4 8 2 9, 1 0 5 5, 9 3 8 2, 4 4 1 0"

    # 3. Setup Git repository
    cd /home/user/telemetry-processor
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    cat << 'EOF' > telemetry_parser.sh
#!/bin/bash
tr -d '!@#$%^&*()\0'
EOF
    chmod +x telemetry_parser.sh
    cp telemetry_parser.sh bin/telemetry_parser_v1.0
    chmod +x bin/telemetry_parser_v1.0

    git add telemetry_parser.sh bin/telemetry_parser_v1.0
    git commit -m "Initial commit"
    git tag v1.0

    for i in $(seq 1 9); do
        echo "# commit $i" >> telemetry_parser.sh
        git commit -am "Commit $i"
    done

    # Introduce bad commit
    cat << 'EOF' > telemetry_parser.sh
#!/bin/bash
tr -d '!@#$%^&*()\0'
# Bug introduced: replace A with B and simulate memory leak
sed 's/A/B/g'
EOF
    git commit -am "Refactor parsing logic"

    for i in $(seq 11 20); do
        echo "# commit $i" >> telemetry_parser.sh
        git commit -am "Commit $i"
    done

    # Create user and fix permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
