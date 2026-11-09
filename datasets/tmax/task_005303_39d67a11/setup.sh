#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip xxd coreutils bash
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/upload_service/sandbox
    cd /home/user/upload_service

    # Create sample plaintext
    cat << 'EOF' > sample.txt
SYSTEM_LOG: Initializing sandboxed environment...
Status: OK
EOF

    # Create the encrypted sample using a 1-byte XOR key (0x42 / 66)
    python3 -c "
key = 0x42
with open('sample.txt', 'rb') as f:
    data = f.read()
with open('sample.enc', 'wb') as f:
    f.write(bytes([b ^ key for b in data]))
"

    # Create the scanner
    cat << 'EOF' > scanner.sh
#!/bin/bash
if grep -q "PWNED" "\$1"; then
    echo "SCANNER ALERT: Malicious signature detected!"
    exit 1
fi
exit 0
EOF
    chmod +x scanner.sh

    # Create the process script
    cat << 'EOF' > process_upload.sh
#!/bin/bash
if [ "\$#" -ne 1 ]; then
    echo "Usage: \$0 <file>"
    exit 1
fi

FILE="\$1"

# Run scanner
./scanner.sh "\$FILE"
if [ \$? -ne 0 ]; then
    exit 1
fi

HEADER=\$(head -n 1 "\$FILE")
if [ "\$HEADER" != "SECURE_PAYLOAD" ]; then
    echo "Invalid payload header."
    exit 1
fi

# Extract the encrypted portion (everything after line 1)
tail -n +2 "\$FILE" > /tmp/payload.enc

# Decrypt and process via python
python3 -c "
import sys, os
key = 0x42
try:
    with open('/tmp/payload.enc', 'rb') as f:
        data = f.read()
    dec = bytes([b ^ key for b in data])
    # The first line is the filename, the rest is content
    parts = dec.split(b'\n', 1)
    if len(parts) == 2:
        filename = parts[0].decode('utf-8').strip()
        content = parts[1]
        target_path = os.path.join('/home/user/upload_service/sandbox', filename)
        with open(target_path, 'wb') as out:
            out.write(content)
        print(f'Successfully extracted to sandbox.')
except Exception as e:
    print('Extraction failed.')
"
rm -f /tmp/payload.enc
EOF
    chmod +x process_upload.sh

    chown -R user:user /home/user/upload_service
    chmod -R 777 /home/user
