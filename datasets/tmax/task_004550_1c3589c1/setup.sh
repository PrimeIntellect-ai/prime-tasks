#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app /home/user/data /home/user/lib /home/user/output

    cat << 'EOF' > /home/user/data/raw.csv
1620000000,192.168.1.1,/api/v1/data,Mozilla
1620000000,192.168.1.1,/api/v1/data,Mozilla
1620000000,192.168.1.1,/api/v1/data,Mozilla
1620000000,10.0.0.5,/api/v1/info,curl
1620000001,192.168.1.1,/api/v1/info,Mozilla
1620000001,192.168.1.1,/api/v1/info,Mozilla
1620000001,192.168.1.1,/api/v1/info,Mozilla
1620000001,192.168.1.1,/api/v1/info,Mozilla
1620000001,invalid_ip_format,/api/v1/test,curl
1620000002,10.0.0.5,/api/v1/data,curl
EOF

    cat << 'EOF' > /home/user/lib/libvalidate.sh
#!/bin/bash
validate_ip() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}
EOF
    chmod +x /home/user/lib/libvalidate.sh

    cat << 'EOF' > /home/user/app/processor.sh
#!/bin/bash
source /home/user/lib/libvalidate.sh

> /home/user/output/final_processed.txt
> /home/user/output/errors.log

while IFS=',' read -r ts ip method endpoint; do
    if ! validate_ip_v2 "$ip"; then
        echo "INVALID IP: $ip" >> /home/user/output/errors.log
        continue
    fi

    if /home/user/app/rate_limiter.sh "$ip" "$ts"; then
        echo "$ts $ip $method $endpoint ACCEPTED" >> /home/user/output/final_processed.txt
    else
        echo "$ts $ip $method $endpoint RATELIMITED" >> /home/user/output/final_processed.txt
    fi
done < /home/user/data/migrated_logs.csv
EOF
    chmod +x /home/user/app/processor.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
