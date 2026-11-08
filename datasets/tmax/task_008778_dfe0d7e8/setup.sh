#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo expect curl
    pip3 install pytest

    mkdir -p /home/user/migration_project/db_service
    mkdir -p /home/user/migration_project/data

    cat << 'EOF' > /home/user/migration_project/db_service/init_db.sh
#!/bin/bash
echo -n "Enter admin password to initialize DB: "
read password
if [ "$password" != "migrate123" ]; then
    echo "Auth failed."
    exit 1
fi
echo "Initializing..."
sleep 3
mkdir -p /home/user/migration_project/data
touch /home/user/migration_project/data/db_ready.flag
echo "DB Ready."
EOF
    chmod +x /home/user/migration_project/db_service/init_db.sh

    cd /home/user/migration_project
    cargo new rust_app
    cat << 'EOF' > /home/user/migration_project/rust_app/src/main.rs
use std::env;
use std::fs;

fn main() {
    let data_path = env::var("DATA_PATH").expect("DATA_PATH not set");
    let flag_file = format!("{}/db_ready.flag", data_path);

    // This panics immediately if the file doesn't exist
    let _content = fs::read_to_string(&flag_file).expect("Failed to read DB flag, DB not ready!");

    fs::write("/home/user/migration_project/app.log", "Connection established\n").unwrap();
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
