#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip parallel
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/simulate.sh
#!/bin/bash
x=$1
y=$2
# artificial delay
sleep 0.05
# Cost function: (x-42)^2 + (y-73)^2
cost=$(( (x - 42) * (x - 42) + (y - 73) * (y - 73) ))
echo "$x $y $cost"
EOF
    chmod +x /home/user/simulate.sh

    python3 -c '
import random
random.seed(42)
with open("/home/user/samples.txt", "w") as f:
    for _ in range(1000):
        f.write(f"{random.randint(0, 100)} {random.randint(0, 100)}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
