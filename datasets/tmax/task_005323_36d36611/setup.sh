#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_env.sh
#!/bin/bash
cd /home/user
wget -q https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2204-7.0.5.tgz
tar -xf mongodb-linux-x86_64-ubuntu2204-7.0.5.tgz
mkdir -p /home/user/db_data
./mongodb-linux-x86_64-ubuntu2204-7.0.5/bin/mongod --dbpath /home/user/db_data --port 27017 --fork --logpath /home/user/mongod.log
sleep 3

# Insert test data
./mongodb-linux-x86_64-ubuntu2204-7.0.5/bin/mongosh --port 27017 --eval '
db = db.getSiblingDB("compliance");
db.access_logs.insertMany([
  { user_id: "u001", role: "guest", endpoint: "/api/admin/users" },
  { user_id: "u001", role: "guest", endpoint: "/api/admin/config" },
  { user_id: "u001", role: "guest", endpoint: "/api/admin/delete" },
  { user_id: "u002", role: "guest", endpoint: "/api/admin/users" },
  { user_id: "u003", role: "admin", endpoint: "/api/admin/users" },
  { user_id: "u003", role: "admin", endpoint: "/api/admin/config" },
  { user_id: "u003", role: "admin", endpoint: "/api/admin/delete" },
  { user_id: "u003", role: "admin", endpoint: "/api/admin/logs" }
]);
'
EOF
    chmod +x /home/user/setup_env.sh

    chmod -R 777 /home/user
