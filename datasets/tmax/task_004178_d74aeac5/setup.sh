#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/test.sh
#!/bin/bash
# Concurrent proxy weight generator
echo "frontend main" > /home/user/proxy.conf

(
    w1=$(/home/user/eval "10 5 + 3 *")
    echo "server backend1 10.0.0.1:$w1" >> /home/user/proxy.conf
) &

(
    w2=$(/home/user/eval "100 10 / 2 *")
    echo "server backend2 10.0.0.2:$w2" >> /home/user/proxy.conf
) &

wait
EOF

chmod +x /home/user/test.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
