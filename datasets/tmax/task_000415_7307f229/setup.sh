#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go procps
pip3 install pytest

mkdir -p /home/user

# Create the mock passwd file
cat << 'EOF' > /home/user/mock_passwd
root:x:0:0:root:/root:/bin/bash
netadmin:x:1001:1001:Network Admin:/home/netadmin:/bin/bash
appuser:x:1002:1002:App User:/home/appuser:/bin/bash
dbdaemon:x:1005:1005:Database Daemon:/var/lib/db:/bin/false
EOF

# Create the connections CSV file
cat << 'EOF' > /home/user/conns.csv
192.168.1.10,10.0.0.5,ESTABLISHED,1001
192.168.1.11,10.0.0.6,TIME_WAIT,1002
192.168.1.12,10.0.0.7,ESTABLISHED,1005
192.168.1.13,10.0.0.8,ESTABLISHED,9999
10.0.0.1,8.8.8.8,LISTEN,0
EOF

# Create the deploy_fstab file
cat << 'EOF' > /home/user/deploy_fstab
# device target_directory fstype options dump pass
tmpfs /home/user/stage_alpha tmpfs rw,nosuid,nodev 0 0
/dev/sdb1 /home/user/stage_beta ext4 defaults 1 2
EOF

# Create dummy netmon_v1 script
cat << 'EOF' > /home/user/netmon_v1
#!/bin/bash
sleep 3600
EOF
chmod +x /home/user/netmon_v1

# Autostart the dummy processes when the container runs
cat << 'EOF' > /.singularity.d/env/99-netmon.sh
#!/bin/sh
/home/user/netmon_v1 >/dev/null 2>&1 &
/home/user/netmon_v1 >/dev/null 2>&1 &
EOF
chmod +x /.singularity.d/env/99-netmon.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
