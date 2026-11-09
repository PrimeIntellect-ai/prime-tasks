#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'LOGEOF' > /home/user/cm_audit.log
System booting up...
Ignoring corrupted block at 0x00FF.

BEGIN_RECORD
TIMESTAMP: 2023-10-27T10:00:00Z
ACTION: ADD_USER
DETAILS: username=jdoe password=SecretPass123! ip=192.168.1.50 shell=/bin/bash
END_RECORD

Some random noise here.

BEGIN_RECORD
TIMESTAMP: 2023-10-27T10:05:12Z
ACTION: UPDATE_FW
DETAILS: rule=allow port=80 ip=10.0.0.12
END_RECORD

BEGIN_RECORD
TIMESTAMP: 2023-10-27T10:15:30Z
ACTION: RESET_PASS
DETAILS: username=admin password=NewAdminPass! ip=172.16.254.1
END_RECORD
LOGEOF

    chmod 644 /home/user/cm_audit.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
