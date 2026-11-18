#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron expect jq
    pip3 install pytest pexpect

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/bin
    mkdir -p /home/user/data/users/alice
    mkdir -p /home/user/data/users/bob
    mkdir -p /home/user/data/users/charlie

    head -c 2000 /dev/urandom > /home/user/data/users/alice/file.dat
    head -c 1000 /dev/urandom > /home/user/data/users/bob/file.dat
    head -c 5000 /dev/urandom > /home/user/data/users/charlie/file.dat

    cat << 'EOF' > /home/user/users_list.txt
alice
bob
charlie
EOF

    cat << 'EOF' > /home/user/quotas.json
{
  "alice": 1500,
  "bob": 2000,
  "charlie": 3000
}
EOF

    cat << 'EOF' > /home/user/bin/legacy_alerter
#!/bin/bash
read -p "Enter username: " uname
read -p "Enter current usage (bytes): " usage
read -p "Enter quota (bytes): " quota
read -p "Confirm alert (y/n)? " confirm

if [ "$confirm" = "y" ]; then
    echo "ALERT: User $uname exceeded quota. Usage: $usage, Quota: $quota" >> /home/user/alert.log
fi
EOF

    chmod +x /home/user/bin/legacy_alerter

    chown -R user:user /home/user
    chmod -R 777 /home/user
