#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy scipy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
x_obs = [i/10.0 for i in range(11)]
u_obs = [0.01, 0.05, 0.15, 0.35, 0.45, 0.45, 0.35, 0.15, 0.05, 0.01, 0.005]
with open('/home/user/observed_variant.csv', 'w') as f:
    f.write("x,observed_u\n")
    for x_val, u_val in zip(x_obs, u_obs):
        f.write(f"{x_val},{u_val}\n")
EOF
python3 /tmp/setup.py

chmod -R 777 /home/user
