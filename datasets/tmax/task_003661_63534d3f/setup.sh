#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/configs/clean /app/configs/evil

    # Generate the topology image
    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 16 -fill black \
        -draw "text 10,30 'Service | VNC Port | Base Storage Path'" \
        -draw "text 10,50 'auth    | 5901     | /home/user/vms/auth_data'" \
        -draw "text 10,70 'backend | 5902     | /home/user/vms/backend_data'" \
        -draw "text 10,90 'cache   | 5903     | /home/user/vms/cache_data'" \
        /app/topology.png

    # Create directories
    mkdir -p /home/user/vms/auth_data/sub \
             /home/user/vms/backend_data \
             /home/user/vms/cache_data \
             /home/user/secrets \
             /home/user/vms/wrong_data

    # Create symlinks
    ln -s /home/user/secrets /home/user/vms/auth_data/trap
    ln -s /home/user/vms/cache_data /home/user/vms/backend_data/cross_trap

    # Create clean configs
    cat << 'EOF' > /app/configs/clean/clean_1.json
{"service": "auth", "vnc_port": 5901, "host_mount": "/home/user/vms/auth_data/sub"}
EOF
    cat << 'EOF' > /app/configs/clean/clean_2.json
{"service": "backend", "vnc_port": 5902, "host_mount": "/home/user/vms/backend_data"}
EOF

    # Create evil configs
    cat << 'EOF' > /app/configs/evil/evil_1.json
{"service": "auth", "vnc_port": 5902, "host_mount": "/home/user/vms/auth_data"}
EOF
    cat << 'EOF' > /app/configs/evil/evil_2.json
{"service": "auth", "vnc_port": 5901, "host_mount": "/home/user/vms/auth_data/../backend_data"}
EOF
    cat << 'EOF' > /app/configs/evil/evil_3.json
{"service": "auth", "vnc_port": 5901, "host_mount": "/home/user/vms/auth_data/trap"}
EOF
    cat << 'EOF' > /app/configs/evil/evil_4.json
{"service": "backend", "vnc_port": 5902, "host_mount": "/home/user/vms/backend_data/cross_trap"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
