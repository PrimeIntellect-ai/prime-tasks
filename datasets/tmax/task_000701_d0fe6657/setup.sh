#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project/scripts
    mkdir -p /home/user/project/logs

    # deps.txt
    cat << 'EOF' > /home/user/project/deps.txt
core:
utils:core
math:utils
graphics:math utils
ui:graphics core
app:ui network
network:crypto
crypto:utils network_base
network_base:network
EOF

    # resolve_deps.sh (buggy)
    cat << 'EOF' > /home/user/project/scripts/resolve_deps.sh
#!/bin/bash
dep=$1
deps=$(grep "^$dep:" /home/user/project/deps.txt | cut -d':' -f2)
for d in $deps; do
    if [ -n "$d" ]; then
        /home/user/project/scripts/resolve_deps.sh "$d"
    fi
done
echo "$dep" >> /home/user/project/resolved.txt
EOF
    chmod +x /home/user/project/scripts/resolve_deps.sh

    # build.sh
    cat << 'EOF' > /home/user/project/build.sh
#!/bin/bash
rm -f /home/user/project/resolved.txt
rm -f /home/user/project/visited.txt
/home/user/project/scripts/resolve_deps.sh app
EOF
    chmod +x /home/user/project/build.sh

    # logs
    cat << 'EOF' > /home/user/project/logs/worker1.log
[2023-10-01T10:00:01] Worker 1 started
[2023-10-01T10:00:05] Worker 1 compiled core
[2023-10-01T10:00:15] Worker 1 compiled utils
EOF

    cat << 'EOF' > /home/user/project/logs/worker2.log
[2023-10-01T10:00:02] Worker 2 started
[2023-10-01T10:00:08] Worker 2 compiled network_base
[2023-10-01T10:00:20] Worker 2 compiled crypto
EOF

    cat << 'EOF' > /home/user/project/logs/download.log
[2023-10-01T09:59:00] Downloaded lib_json in 120ms
[2023-10-01T09:59:02] Downloaded lib_xml in 150ms
[2023-10-01T09:59:05] Downloaded lib_heavy_crypto in 5200ms
[2023-10-01T09:59:12] Downloaded lib_fast in 45ms
EOF

    chown -R user:user /home/user/project
    chmod -R 777 /home/user
