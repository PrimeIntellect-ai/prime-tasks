#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/services

    echo "#!/bin/bash\necho 'Rotating logs...'" > /home/user/services/log_rotate.sh
    echo "#!/bin/bash\necho 'Clearing cache...'" > /home/user/services/cache_clear.sh
    echo "#!/usr/bin/env python3\nprint('Monitoring...')" > /home/user/services/monitor.py

    cat << 'EOF' > /home/user/services/sys_backup.sh
#!/bin/bash
# Legacy backup service
SECRET_HASH="1d6cc4fc958564e1c2dd5dcda3e06180"

echo "Starting backup process..."
# ... backup logic ...
EOF

    chmod -R 777 /home/user

    # Override specific permissions required by the task
    chmod 755 /home/user/services/log_rotate.sh
    chmod 755 /home/user/services/cache_clear.sh
    chmod 755 /home/user/services/monitor.py
    chmod 777 /home/user/services/sys_backup.sh
