#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/ticket_repo
cd /home/user/ticket_repo

git init
git config user.name "Admin"
git config user.email "admin@example.com"

cat << 'EOF' > calculate.sh
#!/bin/bash
DB_PASS="h4ckth3m4th!99"
N=$1
for ((i=1; i<=N; i++)); do
    n=$i
    count=0
    while [ $n -ne 1 ]; do
        if [ $((n % 2)) -eq 0 ]; then
            n=$((n / 2))
        else
            n=$((3 * n + 1))
        fi
        count=$((count + 1))
    done
    echo "$i: $count"
done
EOF

chmod +x calculate.sh
git add calculate.sh
git commit -m "Initial commit with collatz script"

cat << 'EOF' > calculate.sh
#!/bin/bash
N=$1
for ((i=1; i<=N; i++)); do
    n=$i
    count=0
    while [ $n -ne 1 ]; do
        if [ $((n % 2)) -eq 0 ]; then
            n=$((n / 2))
        else
            # Bug: Does not update n
            temp=$((3 * n + 1))
        fi
        count=$((count + 1))
    done
    echo "$i: $count"
done
EOF

git add calculate.sh
git commit -m "remove hardcoded db password and optimize"

chmod -R 777 /home/user
