#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.sh
#!/bin/bash
mkdir -p /home/user/artifacts/train
mkdir -p /home/user/artifacts/test

# Generate random vectors for train
for i in {1..50}; do
    for j in {1..10}; do
        echo "$RANDOM" | awk '{print $1 / 32767.0}' >> /home/user/artifacts/train/train_${i}.txt
    done
done

# Generate random vectors for test
for i in {1..10}; do
    if [ "$i" -eq 7 ]; then
        # Introduce the leak: test_7 is almost identical to train_42
        awk '{print $1 + 0.001}' /home/user/artifacts/train/train_42.txt > /home/user/artifacts/test/test_7.txt
    else
        for j in {1..10}; do
            echo "$RANDOM" | awk '{print $1 / 32767.0}' >> /home/user/artifacts/test/test_${i}.txt
        done
    fi
done
EOF

    bash /tmp/setup.sh
    rm /tmp/setup.sh

    chmod -R 777 /home/user
