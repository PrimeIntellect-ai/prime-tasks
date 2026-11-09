#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget build-essential netcat-openbsd
    pip3 install pytest

    mkdir -p /app
    cd /app
    wget -qO- https://github.com/jpmens/jo/releases/download/1.9/jo-1.9.tar.gz | tar -xz

    # Inject the perturbation
    sed -i 's/LDFLAGS = @LDFLAGS@/LDFALGS = @LDFLAGS@/' /app/jo-1.9/Makefile.in

    # Create test results
    cat <<EOF > /app/test_results_A.txt
unit=pass
integration=pass
build=pass
EOF

    cat <<EOF > /app/test_results_B.txt
deploy=fail
lint=pass
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
