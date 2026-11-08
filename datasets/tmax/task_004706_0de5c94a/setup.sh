#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/repo/bin
    mkdir -p /home/user/repo/lib
    mkdir -p /home/user/repo/docs
    mkdir -p /home/user/backups

    echo -n "app1_binary_data" > /home/user/repo/bin/app_v1
    echo -n "app2_binary_data_new" > /home/user/repo/bin/app_v2
    echo -n "temp_data" > /home/user/repo/bin/cache.tmp
    echo -n "core_lib_v2_data" > /home/user/repo/lib/libcore.so
    echo -n "old_lib_data" > /home/user/repo/lib/libold.so
    echo -n "readme documentation" > /home/user/repo/docs/readme.txt

    cat << 'EOF' > /home/user/repo_config.ini
[Backup]
include_dirs = /home/user/repo/bin,/home/user/repo/lib
exclude_patterns = *.tmp,*.log
hash_algorithm = sha256
EOF

    cat << 'EOF' > /home/user/backups/manifest_v1.json
{
  "bin/app_v1": "93a8d9b15e1cb2f5bde4e019623e160a283e5cde3ba3eb4e82f71b9ebc7e8e50",
  "lib/libcore.so": "5218d6bc9f0dfbaefb565a0b63c769e54a93c72671eebfebe61456a5293297a7",
  "lib/libold.so": "f0ed7a393c0da27dd2392476b7e096fbb525e9854efdfc11c47285a8efb7a701"
}
EOF

    chmod -R 777 /home/user
