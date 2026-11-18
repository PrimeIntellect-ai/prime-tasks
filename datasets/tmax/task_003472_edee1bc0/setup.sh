#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip bc gawk
pip3 install pytest

mkdir -p /home/user

python3 -c '
import random
random.seed(42)
with open("/home/user/data_inputs.txt", "w") as f:
    for i in range(1, 10001):
        if i == 6842:
            f.write("850.1234\n")
        else:
            f.write(f"{random.uniform(10, 100):.4f}\n")
'

cat << 'EOF' > /home/user/reference_transform.sh
#!/bin/bash
# Multiplies each line by 2.71828
awk '{ printf "%.5f\n", $1 * 2.71828 }' "$1"
EOF
chmod +x /home/user/reference_transform.sh

cat << 'EOF' > /home/user/suspicious_transform.sh
#!/bin/bash
# Contains a bug: if the input is greater than 500, it loses precision due to integer casting before multiplication.
awk '{ 
    if ($1 > 500) {
        val = int($1)
        printf "%.5f\n", val * 2.71828
    } else {
        printf "%.5f\n", $1 * 2.71828
    }
}' "$1"
EOF
chmod +x /home/user/suspicious_transform.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
