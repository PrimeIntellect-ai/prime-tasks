#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    # Create the user first to ensure /home/user exists
    useradd -m -s /bin/bash user || true

    # Create the input data file with embedded newlines and commas
    cat << 'EOF' > /home/user/config_changes.csv
ChangeID,Service,ConfigData,Author
101,auth-service,"{
""retries"": 3,
""timeout"": 5000
}",jdoe
102,billing,"""enabled"": true",asmith
103,search,"{
""index"": ""primary""
}",jdoe
104,cache,"{""ttl"": 3600}",bwayne
105,gateway,"{
""rate_limit"": 100,
""burst"": 20,
""strategy"": ""token_bucket""
}",asmith
106,db,"""max_conns"": 500",cjones
EOF

    chmod -R 777 /home/user
