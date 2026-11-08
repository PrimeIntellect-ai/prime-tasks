#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/worker.sh
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: $0 <value>"
    exit 1
fi

VAL=$1

# Decay calculation loop
while [ "$(echo "$VAL > 0.01" | bc -l)" -eq 1 ]; do
    # BUG: Precision loss tracking issue. 
    # printf "%.1f" on 0.05 rounds to 0.1, causing an infinite loop when VAL reaches 0.1
    VAL=$(printf "%.1f" $(echo "$VAL * 0.5" | bc -l))
done

echo "Decay complete: $VAL"
EOF

    chmod +x /home/user/worker.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
