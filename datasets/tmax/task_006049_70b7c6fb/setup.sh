#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip diffutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/data.wal
100,ADD,50,150
101,SUB,10,111
102,ADD,20,122
103,ADD,5,TRUNCATED
104,ADD,15,119
105,SUB,5,100
106,MALFORMED,LINE
107,ADD,10,117
EOF

    cat << 'EOF' > /home/user/app/transform.sh
#!/bin/bash
total=0
while IFS=, read -r ts op val chk; do
    if [ "$op" == "ADD" ]; then total=$((total + val)); fi
    if [ "$op" == "SUB" ]; then total=$((total - val)); fi
done < "$1"
echo "{\"total\": $total}" > /home/user/app/current_state.json
EOF
    chmod +x /home/user/app/transform.sh

    cat << 'EOF' > /home/user/app/known_good.json
{"total": 60}
EOF

    chmod -R 777 /home/user
