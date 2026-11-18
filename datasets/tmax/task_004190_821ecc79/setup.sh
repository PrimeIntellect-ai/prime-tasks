#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config_changes.log
[2023-11-01T10:05:12Z] User=alice Action=Update Target=/ETC//ssh/sshd_config Details="status: success, lines_added: 12"
[2023-11-01T10:05:15Z] User=alice Action=Update Target=/etc/ssh/sshd_config Details="status: success, lines_added: 12"
[2023-11-01T10:45:00Z] User=bob Action=Update Target=/etc/hosts Details="lines_added: 3"
[2023-11-01T11:15:20Z] User=alice Action=Restart Target=nginx Details="status: done"
[2023-11-01T11:16:00Z] User=alice Action=Update Target=/etc/nginx//nginx.conf Details="lines_added: 50"
[2023-11-01T11:17:00Z] User=alice Action=Update Target=/etc/nginx/nginx.conf Details="lines_added: 50"
[2023-11-01T11:20:00Z] User=alice Action=Update Target=/etc/nginx/nginx.conf Details="lines_added: 5"
[2023-11-01T11:25:00Z] User=alice Action=Restart Target=nginx Details="status: done"
EOF

    chmod -R 777 /home/user
