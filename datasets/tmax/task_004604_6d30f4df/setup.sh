#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    mkdir -p /home/user/nginx /home/user/bin /home/user/run

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    upstream backend {
        server unix:/home/user/run/microvm_alpha.sock;
        server unix:/home/user/run/microvm_beta.sock;
        server unix:/home/user/run/microvm_gamma.sock;
    }
    server {
        listen 8080;
        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/bin/qemu_mock.sh
#!/bin/bash
SOCKET_PATH="$1"
touch "$SOCKET_PATH"
# Keep process alive to simulate running VM
while true; do sleep 60; done
EOF
    chmod +x /home/user/bin/qemu_mock.sh

    cat << 'EOF' > /home/user/deploy_vms.sh
#!/bin/bash
# TODO: Parse /home/user/nginx/nginx.conf and do a staged rollout
/home/user/bin/qemu_mock.sh /tmp/vm_1.sock &
/home/user/bin/qemu_mock.sh /tmp/vm_2.sock &
EOF
    chmod +x /home/user/deploy_vms.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
