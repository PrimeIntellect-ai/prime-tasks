#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install Rust
    apt-get install -y cargo rustc

    # Create user
    useradd -m -s /bin/bash user || true

    # Create access logs
    cat << 'EOF' > /home/user/access_logs.csv
timestamp,ip_address,emp_id,status_code,endpoint
2023-10-01T10:00,192.168.1.1,E001,200,/login
2023-10-01T10:05,192.168.1.1,E001,403,/api/admin
2023-10-01T10:06,192.168.1.1,E001,403,/api/admin
2023-10-01T10:07,192.168.1.1,E001,403,/api/admin
2023-10-01T10:08,192.168.1.1,E001,403,/api/admin
2023-10-01T10:00,10.0.0.5,E002,403,/api/salaries
2023-10-01T10:01,10.0.0.5,E002,403,/api/salaries
2023-10-01T10:02,10.0.0.5,E002,200,/api/public
2023-10-01T11:00,172.16.0.2,E003,403,/api/admin
2023-10-01T11:01,172.16.0.2,E003,403,/api/admin
2023-10-01T11:02,172.16.0.2,E003,403,/api/admin
2023-10-01T11:03,172.16.0.2,E003,403,/api/admin
2023-10-01T11:04,172.16.0.2,E003,403,/api/admin
2023-10-01T11:05,172.16.0.2,E004,500,/api/error
EOF

    # Create employee records
    cat << 'EOF' > /home/user/employees.csv
emp_id,full_name,email,department
E001,Alice Smith,alice.smith@corp.com,Engineering
E002,Bob Jones,bjones@corp.com,HR
E003,Charlie Brown,charlieb@corp.com,Sales
E004,Diana Prince,dprince@corp.com,IT
EOF

    # Set permissions
    chmod -R 777 /home/user
