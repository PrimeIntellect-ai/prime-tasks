#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip xxd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/suspicious_dropper.sh
#!/bin/bash
# Obfuscated dropper payload
payload="6d6f632e6c6976652d7265707573"
len=${#payload}
i=0
decoded_hex=""

# Anti-analysis loop logic
while [ $i -lt $len ]; do
    pair=${payload:$i:2}
    decoded_hex="$pair$decoded_hex"

    # Bug: Causes infinite loop when encountering the hex value for '.' (2e)
    if [ "$pair" == "2e" ]; then
        i=$((i + 0))
    else
        i=$((i + 2))
    fi
done

echo "$decoded_hex" | xxd -r -p
echo
EOF

    chmod +x /home/user/suspicious_dropper.sh
    chmod -R 777 /home/user
