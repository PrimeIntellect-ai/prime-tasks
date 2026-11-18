#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq bc
pip3 install pytest

mkdir -p /home/user/data

# Create normal files
dd if=/dev/zero of=/home/user/data/file1.txt bs=1024 count=150 2>/dev/null
dd if=/dev/zero of=/home/user/data/file2.txt bs=1024 count=100 2>/dev/null
dd if=/dev/zero of=/home/user/data/file3.txt bs=1024 count=200 2>/dev/null
dd if=/dev/zero of=/home/user/data/report.txt bs=1024 count=50 2>/dev/null

# Create a file with an ISO-8859-1 (Latin-1) encoded filename (résumé.txt)
python3 -c "
import os
with open(os.path.join(b'/home/user/data', b'r\xe9sum\xe9.txt'), 'wb') as f:
    f.write(b'\x00' * 1024 * 100)
"

# Create the buggy script
cat << 'EOF' > /home/user/process_data.sh
#!/bin/bash
data_dir="/home/user/data"
total_size=0
count=0
files=""

for f in "$data_dir"/*; do
    if [ -f "$f" ]; then
        size=$(stat -c%s "$f")
        total_size=$((total_size + size))
        count=$((count + 1))
        filename=$(basename "$f")
        if [ -z "$files" ]; then
            files="\"$filename\""
        else
            files="$files, \"$filename\""
        fi
    fi
done

# Calculate average size in MB
avg_mb=$(echo "scale=2; $total_size / 1048576 / $count" | bc)

json="{\"average_size_mb\": $avg_mb, \"processed_files\": [$files]}"
echo "$json" > /home/user/summary.json
jq . /home/user/summary.json > /home/user/output.json
EOF

chmod +x /home/user/process_data.sh

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/data /home/user/process_data.sh
chmod -R 777 /home/user
