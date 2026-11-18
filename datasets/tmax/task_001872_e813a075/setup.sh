#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-openbsd gawk
    pip3 install pytest

    # Create the oracle script
    mkdir -p /app
    cat << 'EOF' > /app/oracle_mapper.sh
#!/bin/bash
awk -F'[ =]' '{
    id=$2; val=$4; op_raw=$6; ip_raw=$8;

    # Mask IP
    split(ip_raw, ip_parts, ".");
    masked_ip = ip_parts[1] "." ip_parts[2] ".X.X";

    # Decode OP and calculate
    if (op_raw == "\\u002B") { result = val + id; }
    else if (op_raw == "\\u002D") { result = val - id; }
    else if (op_raw == "\\u002A") { result = val * id; }
    else { result = 0; }

    # Window aggregation
    w3=w2; w2=w1; w1=result;
    rolling_sum = w1 + w2 + w3;

    print "[" masked_ip "] ROLLING_SUM=" rolling_sum;
}'
EOF
    chmod +x /app/oracle_mapper.sh

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
