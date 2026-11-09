#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip socat
pip3 install pytest

mkdir -p /home/user/logs

# Log file 1 - Success
cat << 'EOF' > /home/user/logs/deploy_1.log
Connecting to host server-web-01 [10.0.0.5] port 22.
Connection established.
Authentication succeeded (publickey).
Deployment completed successfully.
EOF

# Log file 2 - Failure
cat << 'EOF' > /home/user/logs/deploy_2.log
Connecting to host server-db-02 [10.0.0.12] port 22.
Connection established.
debug1: send_pubkey_test: no mutual signature algorithm
Connection closed by authenticating user deploy
Deployment failed.
EOF

# Log file 3 - Success
cat << 'EOF' > /home/user/logs/deploy_3.log
Connecting to host server-app-03 [10.0.0.22] port 22.
Connection established.
Authentication succeeded (publickey).
Deployment completed successfully.
EOF

# Log file 4 - Failure
cat << 'EOF' > /home/user/logs/deploy_4.log
Connecting to host server-cache-01 [10.0.0.8] port 22.
Connection established.
debug1: send_pubkey_test: no mutual signature algorithm
Connection closed by authenticating user deploy
Deployment failed.
EOF

# Create the buggy agent
cat << 'EOF' > /home/user/deploy_agent.sh
#!/bin/bash
if [ ! -f /tmp/agent_runs ]; then
    echo 1 > /tmp/agent_runs
    exit 1
fi
runs=$(cat /tmp/agent_runs)
if [ $runs -lt 3 ]; then
    echo $((runs + 1)) > /tmp/agent_runs
    exit 1
else
    exit 0
fi
EOF
chmod +x /home/user/deploy_agent.sh

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
