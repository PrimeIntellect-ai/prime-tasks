#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user
cd /home/user

cat << 'EOF' > /home/user/apply_wal.sh
#!/bin/bash
MAX_SEQ=$1
LOG_FILE="/home/user/wal_recovered.log"

if [ -z "$MAX_SEQ" ]; then
    echo "Provide max seq"
    exit 1
fi

if [ ! -f "$LOG_FILE" ]; then
    echo "WAL not found"
    exit 1
fi

declare -A DB

while IFS='|' read -r seq action key val chk; do
    # BUG: off by one. Should be -gt
    if [ "$seq" -ge "$MAX_SEQ" ]; then
        break
    fi

    if [ "$val" == "CRASH_TRIGGER_992" ]; then
        echo "FATAL: State corruption detected at seq $seq!"
        exit 1
    fi

    if [ "$action" == "SET" ]; then
        DB["$key"]=$val
    fi
done < "$LOG_FILE"
echo "Success"
exit 0
EOF

chmod +x /home/user/apply_wal.sh

# Generate WAL
cat << 'EOF' > /home/user/generate_wal.sh
#!/bin/bash
> /home/user/wal.log
for i in {1..500}; do
    KEY="key_$((i%50))"
    VAL="val_$(($RANDOM))"

    if [ $i -eq 312 ]; then
        VAL="CRASH_TRIGGER_992"
    fi

    CHK=$(echo -n "$KEY$VAL" | wc -c)

    # Introduce corruption
    if [ $i -eq 45 ]; then
        echo "$i|SET|$KEY|$VAL|999" >> /home/user/wal.log
    elif [ $i -eq 120 ]; then
        echo "$i|SET|$KEY" >> /home/user/wal.log
    elif [ $i -eq 400 ]; then
        echo "garbage data" >> /home/user/wal.log
    else
        echo "$i|SET|$KEY|$VAL|$CHK" >> /home/user/wal.log
    fi
done
EOF

bash /home/user/generate_wal.sh
rm /home/user/generate_wal.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
