#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/investigation/bin
    echo "echo 'normal'" > /home/user/investigation/bin/app1
    echo "echo 'normal2'" > /home/user/investigation/bin/app2
    echo "echo 'malicious'" > /home/user/investigation/bin/sys_update

    # Compute legitimate hashes
    sha256sum /home/user/investigation/bin/app1 > /home/user/investigation/hashes.sha256
    sha256sum /home/user/investigation/bin/app2 >> /home/user/investigation/hashes.sha256

    # Add a fake/old hash for sys_update to simulate tampering
    echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  /home/user/investigation/bin/sys_update" >> /home/user/investigation/hashes.sha256

    cat << 'EOF' > /home/user/investigation/auth.log
Jul 14 12:30:01 server1 crond[1234]: (root) CMD (/usr/lib/sysstat/sa1 1 1)
Jul 14 12:34:55 server1 custom_suid_audit: user maluser executed /home/user/investigation/bin/sys_update
Jul 14 12:34:56 server1 su: pam_unix(su:session): session opened for user root by maluser(uid=1001)
Jul 14 12:35:01 server1 crond[1235]: (root) CMD (run-parts /etc/cron.hourly)
EOF

    chmod -R 777 /home/user

    # Apply specific permissions after the global chmod
    chmod 755 /home/user/investigation/bin/app1
    chmod 755 /home/user/investigation/bin/app2
    chmod 4755 /home/user/investigation/bin/sys_update
