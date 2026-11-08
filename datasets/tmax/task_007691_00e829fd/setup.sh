#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    # Create the binary file
    python3 -c "
import struct
with open('/home/user/telemetry.bin', 'wb') as f:
    name_bytes = 'Sensor-Δ'.encode('utf-8')
    f.write(bytes([len(name_bytes)]))
    f.write(name_bytes)
    f.write(struct.pack('>d', 12345.6789))
"

    # Create the buggy Python script
    cat << 'EOF' > /home/user/parse_telemetry.py
import struct
import sys

def main():
    with open('/home/user/telemetry.bin', 'rb') as f:
        data = f.read()

    # BUG: off by one error (data[1:length] instead of data[1:1+length])
    length = data[0]
    string_data = data[1:length]

    # BUG: float data misaligned due to previous off-by-one
    float_data = data[length:length+8]

    device_name = string_data.decode('utf-8')
    val = struct.unpack('>d', float_data)[0]

    print(f"Device: {device_name}, Value: {val}")

if __name__ == "__main__":
    main()
EOF
    chmod +x /home/user/parse_telemetry.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
