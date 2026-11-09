#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/init_server.sh
#!/bin/bash
echo -n "Enter Server Name: "
read srv_name
echo -n "Enter Port: "
read port
echo -n "Enter Directory: "
read dir
mkdir -p "$dir"
echo "$srv_name" > "$dir/index.html"
echo "PORT=$port" > /home/user/server.conf
echo "DIR=$dir" >> /home/user/server.conf
echo "Configuration saved."
EOF
    chmod +x /home/user/init_server.sh

    chmod -R 777 /home/user
