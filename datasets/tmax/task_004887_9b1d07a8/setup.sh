#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl systemd
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/app/corpora/clean
mkdir -p /home/user/app/corpora/evil
mkdir -p /home/user/.config/systemd/user

cat << 'EOF' > /home/user/app/corpora/clean/clean1.jsonl
{"env": "prod", "cost": 1.5}
{"env": "prod", "cost": 100}
EOF

cat << 'EOF' > /home/user/app/corpora/evil/evil1.jsonl
{"env": "dev", "cost": 5.0}
{"env": "prod", "cost": 0}
{"env": "test", "cost": 10}
{"env": "prod"}
EOF

cat << 'EOF' > /home/user/app/run-aggregator.sh
#!/bin/bash
tail -F /home/user/app/usage.log | xargs -I {} curl -s -X POST -H "Content-Type: application/json" -d "{}" http://localhost:8080/billing
EOF
chmod +x /home/user/app/run-aggregator.sh

cat << 'EOF' > /home/user/.config/systemd/user/cost-aggregator.service
[Unit]
Description=Cost Aggregator Service

[Service]
ExecStart=/home/user/app/run-aggregator.sh

[Install]
WantedBy=default.target
EOF

cat << 'EOF' > /home/user/.config/systemd/user/billing-receiver.service
[Unit]
Description=Billing Receiver Service

[Service]
ExecStart=/usr/bin/python3 -m http.server 8080 --directory /tmp
Restart=always

[Install]
WantedBy=default.target
EOF

cat << 'EOF' > /home/user/.config/systemd/user/log-generator.service
[Unit]
Description=Log Generator Service

[Service]
ExecStart=/bin/bash -c 'while true; do echo "{\"env\": \"prod\", \"cost\": 1.5}" >> /home/user/app/usage.log; sleep 1; done'
Restart=always

[Install]
WantedBy=default.target
EOF

touch /home/user/app/usage.log

chmod -R 777 /home/user
