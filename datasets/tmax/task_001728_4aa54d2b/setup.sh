#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/.cloud_db
C-101,5.00,80,70,running
C-102,3.50,2,5,running
C-103,1.00,4,8,running
C-104,4.20,1,1,running
C-105,2.50,15,5,running
EOF

    cat << 'EOF' > /home/user/cloud-manager
#!/bin/bash

if [ "$1" == "login" ]; then
    read -p "Username: " user
    read -sp "Password: " pass
    echo ""
    if [ "$user" == "finops_admin" ] && [ "$pass" == "CostSave2023!" ]; then
        touch /home/user/.cloud_session
        echo "Login successful."
        exit 0
    else
        echo "Login failed."
        exit 1
    fi
fi

if [ ! -f /home/user/.cloud_session ]; then
    echo "Error: Not logged in."
    exit 1
fi

if [ "$1" == "list" ]; then
    echo "ContainerID,CostPerHr,CPU_Percent,Mem_Percent"
    grep "running$" /home/user/.cloud_db | awk -F',' '{print $1","$2","$3","$4}'
    exit 0
fi

if [ "$1" == "terminate" ]; then
    if [ -z "$2" ]; then
        echo "Error: Missing ContainerID"
        exit 1
    fi
    cid="$2"
    read -p "Are you sure you want to terminate $cid? [y/N]: " confirm
    if [ "$confirm" == "y" ]; then
        sed -i "s/^$cid,\(.*\),running$/$cid,\1,terminated/" /home/user/.cloud_db
        echo "Terminated $cid"
        exit 0
    else
        echo "Aborted."
        exit 1
    fi
fi

echo "Usage: cloud-manager [login|list|terminate <ID>]"
exit 1
EOF

    chmod +x /home/user/cloud-manager
    chmod -R 777 /home/user
