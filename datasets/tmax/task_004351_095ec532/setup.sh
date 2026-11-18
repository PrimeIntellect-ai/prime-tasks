#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip expect
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/appliance_fs

# Create the initial auth config that silently rejects logins
cat << 'EOF' > /home/user/appliance_fs/auth.conf
auth_type=key
admin_user=admin
admin_pass=admin123
EOF

# Create the mock appliance CLI
cat << 'EOF' > /home/user/appliance_cli.sh
#!/bin/bash

AUTH_FILE="/home/user/appliance_fs/auth.conf"
NET_FILE="/home/user/appliance_fs/network.conf"

source "$AUTH_FILE"

echo -n "Login: "
read -r user

if [ "$auth_type" = "key" ]; then
    # Silently reject
    exit 1
fi

echo -n "Password: "
read -r pass

if [ "$user" != "$admin_user" ] || [ "$pass" != "$admin_pass" ]; then
    echo "Authentication failed."
    exit 1
fi

echo "Welcome to ApplianceOS 4.2"
INTERFACE=""
ROUTE=""

while true; do
    echo -n "appliance> "
    read -r cmd args

    if [ "$cmd" = "exit" ]; then
        break
    elif [ "$cmd" = "set" ]; then
        set -- $args
        if [ "$1" = "interface" ]; then
            INTERFACE="$2 $3"
        elif [ "$1" = "route" ]; then
            ROUTE="$2 $3"
        fi
    elif [ "$cmd" = "commit" ]; then
        echo "interface=$INTERFACE" > "$NET_FILE"
        echo "route=$ROUTE" >> "$NET_FILE"
        echo "DEPLOYMENT_SUCCESS" > /home/user/deploy.log
        echo "Configuration committed."
    fi
done
EOF
chmod +x /home/user/appliance_cli.sh

chmod -R 777 /home/user
