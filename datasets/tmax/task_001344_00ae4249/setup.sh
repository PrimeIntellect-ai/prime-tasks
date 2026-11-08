#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/restore_requests.log
BEGIN_RECORD
ID: REQ001
BASE: /backups/user1
FILE: documents/tax_return.pdf
END_RECORD

BEGIN_RECORD
ID: REQ002
BASE: /backups/user2
FILE: ../../etc/passwd
END_RECORD

BEGIN_RECORD
ID: REQ003
BASE: /backups/user3
FILE: data/./../data/./file.txt
END_RECORD

BEGIN_RECORD
ID: REQ004
BASE: /backups/user4
FILE: safe_dir/../another_safe_dir/file.bin
END_RECORD

BEGIN_RECORD
ID: REQ005
BASE: /backups/user5
FILE: a/b/c/../../../../tmp/hacked
END_RECORD

BEGIN_RECORD
ID: REQ006
BASE: /backups/user6
FILE: /var/log/syslog
END_RECORD

BEGIN_RECORD
ID: REQ007
BASE: /backups/user7
FILE: just_a_file.txt
END_RECORD
EOF

    cat << 'EOF' > /tmp/expected_alerts.csv
ID,FILE
REQ002,../../etc/passwd
REQ005,a/b/c/../../../../tmp/hacked
REQ006,/var/log/syslog
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
