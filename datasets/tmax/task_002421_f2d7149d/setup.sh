#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ruby
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/supervisor /home/user/logs /home/user/mail

    cat << 'EOF' > /home/user/run_task.sh
#!/bin/bash
# Simulates a stripped cron environment
env -i /bin/bash -c "cd /home/user && python3 supervisor/monitor.py"
EOF
    chmod +x /home/user/run_task.sh

    cat << 'EOF' > /home/user/supervisor/monitor.py
import subprocess
import os

try:
    # Fails because PATH is empty and it's a relative command
    subprocess.run(["ssh_manager.sh"], check=True)
    print("Success")
except Exception as e:
    # Writes to wrong location
    with open("error.log", "a") as f:
        f.write(str(e) + "\n")
EOF

    cat << 'EOF' > /home/user/supervisor/ssh_manager.sh
#!/bin/bash
# TODO: Log the SSH port forwarding command
exit 1
EOF
    chmod +x /home/user/supervisor/ssh_manager.sh

    chown -R user:user /home/user
    chmod -R 777 /home/user
