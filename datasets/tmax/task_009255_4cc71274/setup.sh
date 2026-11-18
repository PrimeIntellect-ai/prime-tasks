#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/legacy-deploy.sh
#!/bin/bash
# /home/user/legacy-deploy.sh
echo -n "Target environment (alpha/beta/prod): "
read ENV
if [ "$ENV" != "alpha" ] && [ "$ENV" != "beta" ] && [ "$ENV" != "prod" ]; then
    echo "Invalid environment"
    exit 1
fi
echo -n "Confirm deployment to $ENV (yes/no): "
read CONFIRM
if [ "$CONFIRM" == "yes" ]; then
    echo "Deployment to $ENV successful."
    echo "$ENV" > /home/user/deployed_env.log
    exit 0
else
    echo "Deployment aborted."
    exit 1
fi
EOF

chmod +x /home/user/legacy-deploy.sh

chmod -R 777 /home/user
