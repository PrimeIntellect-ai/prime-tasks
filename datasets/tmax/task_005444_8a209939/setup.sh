#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/system_scripts

# Safe files
echo '#!/bin/bash' > /home/user/system_scripts/safe1.sh
echo 'echo "Doing safe tasks"' >> /home/user/system_scripts/safe1.sh

echo '#!/bin/bash' > /home/user/system_scripts/safe2.sh
echo 'ls -la' >> /home/user/system_scripts/safe2.sh

echo 'setting=123' > /home/user/system_scripts/config.txt

# Vulnerable script
cat << 'EOF' > /home/user/system_scripts/process_data.sh
#!/bin/bash
# Data processor
INPUT_FILE="/home/user/input.dat"
if [ -f "$INPUT_FILE" ]; then
    ENCODED_DATA=$(cat "$INPUT_FILE")
    DECODED_DATA=$(echo "$ENCODED_DATA" | base64 -d)
    # Unsafe execution of decoded data
    eval "$DECODED_DATA"
else
    echo "No input file found."
fi
EOF

# Create an empty input file to prevent errors before payload delivery
touch /home/user/input.dat

# Apply wide permissions first as requested
chmod -R 777 /home/user

# Fix specific file permissions that are tested
chmod 755 /home/user/system_scripts/safe1.sh
chmod 755 /home/user/system_scripts/safe2.sh
chmod 666 /home/user/system_scripts/config.txt
chmod 777 /home/user/system_scripts/process_data.sh
