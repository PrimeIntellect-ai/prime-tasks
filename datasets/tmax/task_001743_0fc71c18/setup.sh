#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest pandas

    # Create required directories
    mkdir -p /home/user/raw_data /home/user/clean_data

    # Create input CSV file
    cat << 'EOF' > /home/user/raw_data/employees.csv
id,name,email,ssn
1,Alice Smith,alices@company.com,123-45-6789
2,Bob Jones,bjones_99@test.org,987-65-4321
3,Charlie Brown,cbrown@domain.net,555-00-1111
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
