#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip expect g++
pip3 install pytest

mkdir -p /home/user/microservices/backups
mkdir -p /home/user/microservices/vols/db
mkdir -p /home/user/microservices/vols/pay
mkdir -p /home/user/microservices/vols/auth

cat << 'EOF' > /home/user/microservices/service.log
[INFO] Service auth started
[ERROR] Service db_backend crashed with code 137
[INFO] Service cache running properly
[WARN] Service auth high memory usage
[ERROR] Service payment_gateway crashed with code 139
EOF

cat << 'EOF' > /home/user/microservices/volumes.fstab
db_backend /home/user/microservices/backups/db.tar /home/user/microservices/vols/db
payment_gateway /home/user/microservices/backups/pay.tar /home/user/microservices/vols/pay
auth /home/user/microservices/backups/auth.tar /home/user/microservices/vols/auth
EOF

cat << 'EOF' > /home/user/microservices/extract_backup.sh
#!/bin/bash
read -p "Enter password: " pass
if [ "$pass" = "secret_vault" ]; then
    echo "Restored files from $1 to $2"
    touch "$2/restored_data.txt"
    exit 0
else
    echo "Access denied."
    exit 1
fi
EOF
chmod +x /home/user/microservices/extract_backup.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
