#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/dashboard-repo.git
git init --bare /home/user/dashboard-repo.git
mkdir -p /home/user/dashboards_deployed

cat << 'EOF' > /home/user/mock_dashboard_service.sh
#!/bin/bash
echo $$ > /home/user/dashboard.pid
trap 'echo "Reloaded" > /home/user/service_reloaded.txt' SIGHUP
while true; do sleep 1; done
EOF
chmod +x /home/user/mock_dashboard_service.sh

# Start the mock service automatically when the container is executed
cat << 'EOF' >> $APPTAINER_ENVIRONMENT
if [ ! -f /home/user/dashboard.pid ] || ! kill -0 $(cat /home/user/dashboard.pid 2>/dev/null) 2>/dev/null; then
    nohup /home/user/mock_dashboard_service.sh > /dev/null 2>&1 &
    sleep 0.5
fi
EOF

chmod -R 777 /home/user
