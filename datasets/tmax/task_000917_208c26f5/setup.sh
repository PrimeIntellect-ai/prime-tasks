#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

apt-get install -y bindfs openssh-server openssh-client golang-go nginx redis-server curl sudo
pip3 install flask redis

useradd -m -s /bin/bash user || true

mkdir -p /home/user/app/config_source
mkdir -p /home/user/app/config_mount
mkdir -p /home/user/app/filter
mkdir -p /home/user/corpus
mkdir -p /home/user/.config/systemd/user

cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
echo "Starting services..."
EOF
chmod +x /home/user/app/start_services.sh

mkdir -p /home/user/.ssh
ssh-keygen -t ed25519 -f /home/user/.ssh/id_ed25519 -N ""
cat /home/user/.ssh/id_ed25519.pub >> /home/user/.ssh/authorized_keys

cat << 'EOF' > /home/user/corpus/clean_metrics.jsonl
{"metric_name": "cpu_usage", "metric_value": 45.2, "tags": ["host=server1"]}
EOF

cat << 'EOF' > /home/user/corpus/evil_metrics.jsonl
{"metric_name": "cpu_usage", "metric_value": -10.0, "tags": ["host=server1"]}
{"metric_name": "DROP_TABLE_users", "metric_value": 10.0, "tags": ["host=server1"]}
{"metric_name": "cpu_usage", "metric_value": 10.0, "tags": ["this_tag_is_way_too_long_and_exceeds_the_fifty_character_limit_easily"]}
EOF

echo "StrictModes no" >> /etc/ssh/sshd_config

chown -R user:user /home/user
chmod -R 777 /home/user
