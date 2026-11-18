#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc build-essential
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/logs
mkdir -p /home/user/tenants/baseline
mkdir -p /home/user/tenants/tenant_1 /home/user/tenants/tenant_2 /home/user/tenants/tenant_3 /home/user/tenants/tenant_4 /home/user/tenants/tenant_5

# Create baseline config
echo '{"tier": "standard", "limits": 100}' > /home/user/tenants/baseline/config.json

# Create identical configs for tenants 1, 3, 4
cp /home/user/tenants/baseline/config.json /home/user/tenants/tenant_1/config.json
cp /home/user/tenants/baseline/config.json /home/user/tenants/tenant_3/config.json
cp /home/user/tenants/baseline/config.json /home/user/tenants/tenant_4/config.json

# Create different configs for tenants 2, 5
echo '{"tier": "premium", "limits": 500}' > /home/user/tenants/tenant_2/config.json
echo '{"tier": "enterprise", "limits": 2000}' > /home/user/tenants/tenant_5/config.json

# Create dummy billing service
cat << 'EOF' > /home/user/billing_service.sh
#!/bin/bash
trap 'echo "Log reopened" > /home/user/logs/billing.log' SIGUSR1
echo $$ > /home/user/logs/billing.pid
echo "Log initialized" > /home/user/logs/billing.log
while true; do
    echo "Billing transaction..." >> /home/user/logs/billing.log
    sleep 0.5
done
EOF
chmod +x /home/user/billing_service.sh

# Start the service
nohup /home/user/billing_service.sh > /dev/null 2>&1 &

chown -R user:user /home/user
chmod -R 777 /home/user
