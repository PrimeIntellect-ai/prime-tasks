#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

mkdir -p /home/user/backups
mkdir -p /home/user/restored

# Generate backup_manifest.log
cat << 'EOF' > /home/user/backup_manifest.log
Job-ID: 8081
Archive: /home/user/backups/syslog.bin
Status: SUCCESS

Job-ID: 8082
Archive: /home/user/backups/corrupt.bin
Status: FAILED

Job-ID: 8083
Archive: /home/user/backups/metrics.bin
Status: SUCCESS
EOF

# Python script to generate the .bin files
cat << 'EOF' > /home/user/setup_bins.py
import struct

def create_bin(filepath, original_name, data_string):
    with open(filepath, 'wb') as f:
        # Magic
        f.write(b'BKUP')
        # Filename (32 bytes null-padded)
        name_bytes = original_name.encode('ascii')
        f.write(name_bytes + b'\x00' * (32 - len(name_bytes)))

        # RLE Payload
        if not data_string:
            return

        current_char = data_string[0]
        count = 1

        for char in data_string[1:]:
            if char == current_char and count < 255:
                count += 1
            else:
                f.write(struct.pack('B', count))
                f.write(current_char.encode('ascii'))
                current_char = char
                count = 1

        f.write(struct.pack('B', count))
        f.write(current_char.encode('ascii'))

# Create syslog.bin (extracts to system_log.txt)
create_bin('/home/user/backups/syslog.bin', 'system_log.txt', 'INFO: System booted successfully.\n' * 5)

# Create metrics.bin (extracts to cpu_metrics.csv)
create_bin('/home/user/backups/metrics.bin', 'cpu_metrics.csv', 'cpu0,100\ncpu1,98\ncpu2,100\n')

# Create a failed job file just in case the agent processes it
create_bin('/home/user/backups/corrupt.bin', 'do_not_restore.txt', 'This should not be restored.')

EOF

python3 /home/user/setup_bins.py
rm /home/user/setup_bins.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
