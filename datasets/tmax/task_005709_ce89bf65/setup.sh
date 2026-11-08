#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nlohmann-json3-dev docker.io wget curl
    pip3 install pytest

    # Install mongosh and mongo tools
    wget -qO- https://downloads.mongodb.com/compass/mongosh-2.1.5-linux-x64.tgz | tar xz
    cp mongosh-2.1.5-linux-x64/bin/* /usr/local/bin/ || true

    wget -qO- https://fastdl.mongodb.org/tools/db/mongodb-database-tools-ubuntu2204-x86_64-100.9.4.tgz | tar xz
    cp mongodb-database-tools-ubuntu2204-x86_64-100.9.4/bin/* /usr/local/bin/ || true

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/employees.csv
emp_id,manager_id,name,salary
E1,,Alice,100000
E2,E1,Bob,80000
E3,E1,Charlie,75000
E4,E2,Dave,60000
E5,E2,Eve,65000
E6,E3,Frank,50000
E7,E6,Grace,45000
EOF

    chmod -R 777 /home/user
