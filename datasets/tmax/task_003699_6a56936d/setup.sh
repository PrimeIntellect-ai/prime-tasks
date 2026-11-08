#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/docs/src
    mkdir -p /home/user/docs/published
    mkdir -p /home/user/docs/backups

    cat << 'EOF' > /home/user/simulate_writer.sh
#!/bin/bash
echo "Starting writer simulation..."
sleep 1
echo "# Chapter 1" > /home/user/docs/src/ch1.md
sleep 1.5
mkdir -p /home/user/docs/src/assets
echo "image data" > /home/user/docs/src/assets/logo.png
sleep 1.5
echo "More content" >> /home/user/docs/src/ch1.md
sleep 1.5
echo "Draft" > /home/user/docs/src/draft.md
sleep 1.5
rm /home/user/docs/src/draft.md
sleep 1
echo "Simulation complete."
EOF
    chmod +x /home/user/simulate_writer.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
