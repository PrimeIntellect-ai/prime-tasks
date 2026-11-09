#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/app/data
    mkdir -p /home/user/bin

    # Create dummy log files to trigger the simulated quota
    head -c 10M </dev/urandom > /home/user/app/data/app-01.log
    head -c 5M </dev/urandom > /home/user/app/data/app-02.log
    head -c 2M </dev/urandom > /home/user/app/data/app-03.log

    # Create the registry file
    cat << 'EOF' > /home/user/app/registry.txt
2023-10-01 | app-01.log | PROCESSED
2023-10-02 | app-02.log | PROCESSED
2023-10-03 | app-03.log | PENDING
EOF

    # Create the broken cleanup script
    cat << 'EOF' > /home/user/bin/cleanup.sh
#!/bin/bash
# Broken pipeline that does nothing
cat /home/user/app/registry.txt | grep "OLD" > /dev/null
EOF
    chmod +x /home/user/bin/cleanup.sh

    # Create the service runner simulating the quota check
    cat << 'EOF' > /home/user/bin/service-runner
#!/bin/bash
SIZE=$(du -k /home/user/app/data | cut -f1)
if [ "$SIZE" -gt 10240 ]; then
    echo "FATAL: /home/user/app/data exceeds 10MB quota. Service failed to start."
    exit 1
fi
echo "Service started successfully."
exit 0
EOF
    chmod +x /home/user/bin/service-runner

    # Create the deployment script
    cat << 'EOF' > /home/user/deploy.sh
#!/bin/bash
echo "Starting CI/CD local deployment..."
/home/user/bin/service-runner
EOF
    chmod +x /home/user/deploy.sh

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure correct permissions
    chmod -R 777 /home/user
