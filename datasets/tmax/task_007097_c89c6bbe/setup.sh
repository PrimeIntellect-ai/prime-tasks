#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_exports.log
INFO: System startup complete.
DEBUG: scanning repository...
INFO: [ARTIFACT] name=core-lib v=1.0 ; requires=utils-lib,math-lib
WARN: deprecated function used in core-lib
INFO: [ARTIFACT] name=utils-lib v=2.1 ; requires=logger-lib
INFO: [ARTIFACT] name=logger-lib v=1.1 ; requires=core-lib
DEBUG: skipping empty artifact
INFO: [ARTIFACT] name=math-lib v=3.0 ; requires=NONE
INFO: [ARTIFACT] name=app-server v=1.0 ; requires=core-lib,web-lib
INFO: [ARTIFACT] name=web-lib v=1.0 ; requires=app-server
INFO: [ARTIFACT] name=standalone v=1.0 ; requires=NONE
INFO: [ARTIFACT] name=db-connector v=2.0 ; requires=orm-fw
INFO: [ARTIFACT] name=orm-fw v=1.5 ; requires=db-connector
INFO: [ARTIFACT] name=frontend-ui v=4.2 ; requires=web-lib
EOF

    chmod -R 777 /home/user
