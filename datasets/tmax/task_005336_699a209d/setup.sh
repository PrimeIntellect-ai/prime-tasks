#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y imagemagick tesseract-ocr expect cargo rustc

    # Create directories
    mkdir -p /app
    mkdir -p /home/user

    # Create the mock VM console
    cat << 'EOF' > /app/vm_console.sh
#!/bin/bash
echo "Booting VM [QEMU/KVM]..."
sleep 1
echo "System ready."
echo -n "login: "
read username
echo -n "Password: "
read -s password
echo ""

if [ "$username" = "admin" ] && [ "$password" = "root123" ]; then
    while true; do
        echo -n "root@vm:~# "
        read cmd
        if [ "$cmd" = "exit" ]; then
            exit 0
        fi
        # mock execution
    done
else
    echo "Login incorrect"
    exit 1
fi
EOF
    chmod +x /app/vm_console.sh

    # Create the image fixture
    convert -size 400x200 canvas:white -fill black -pointsize 24 -draw "text 20,50 'DEPLOYMENT ARCHITECTURE'" -draw "text 20,100 'AUTH_TOKEN: S3cr3t_R0ll0ut'" -draw "text 20,150 'PORT: 8181'" /app/deploy_config.png

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
