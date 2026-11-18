#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/srv1.log
1672531200 [INFO] Service A started
1672531205 [DEBUG] Connecting to DB
1672531215 [INFO] DB connected
EOF

    cat << 'EOF' > /home/user/logs/srv2.log
1672531202 [INFO] Service B started
1672531210 [WARN] High memory usage
1672531220 [INFO] Shutdown
EOF

    cat << 'EOF' > /home/user/merge_timeline.sh
#!/bin/bash
file1=$1
file2=$2

if [ ! -s "$file1" ] && [ ! -s "$file2" ]; then
    exit 1 # Crash on empty files
fi

cat "$file1" "$file2" | sort -n > /tmp/merged.tmp
total=$(wc -l < /tmp/merged.tmp)

# Off by one error: stops one line short
for i in $(seq 1 $((total - 1))); do
    sed -n "${i}p" /tmp/merged.tmp
done
rm /tmp/merged.tmp
EOF

    chmod +x /home/user/merge_timeline.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
