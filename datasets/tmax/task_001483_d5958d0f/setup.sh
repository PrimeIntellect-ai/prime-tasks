#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo cron
pip3 install pytest

mkdir -p /home/user/data
cat << 'EOF' > /home/user/data/raw_users.csv
name,email,notes
Alice Smith, ALICE@example.com ,Account created. UserID: 100001
Bob Jones,  bob.jones@Test.org, "Pending verification, id: 100002"
Charlie Brown,charlie@domain.com, "No ID here!"
Alice S., aLiCe@ExAmPlE.com, "Duplicate entry ID-100001"
Dave Miller, dave@miller.net, "Notes: User ID 100003."
Eve Adams, eve@adams.co, "id - 100003"
EOF

# Create the Cargo project
cargo new /home/user/csv_processor

# Add dependencies to Cargo.toml
cat << 'EOF' >> /home/user/csv_processor/Cargo.toml
csv = "1.3"
regex = "1.10"
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
