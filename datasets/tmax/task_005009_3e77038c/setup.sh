#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bash sed grep coreutils
    pip3 install pytest

    mkdir -p /app/bash-json-parser
    cat << 'EOF' > /app/bash-json-parser/parse.sh
#!/bin/bash
if [[ "$1" =~ \\u[0-9a-fA-F]{4} ]]; then exit 1; fi
metric=$(echo "$1" | sed -n 's/.*"metric": *"\([^"]*\)".*/\1/p')
value=$(echo "$1" | sed -n 's/.*"value": *\([0-9]*\).*/\1/p')
echo "metric=$metric"
echo "value=$value"
EOF
    chmod +x /app/bash-json-parser/parse.sh

    mkdir -p /oracle
    cat << 'EOF' > /oracle/process_configs_oracle.sh
#!/bin/bash
# Oracle script implementing the exact sliding window logic
window=()
while read -r line; do
    # Simple regex extraction acting as the "fixed" parser
    if echo "$line" | grep -q '"metric": *"memory_weight"'; then
        val=$(echo "$line" | sed -n 's/.*"value": *\([0-9]*\).*/\1/p')
        if [ -n "$val" ]; then
            window+=("$val")
            if [ ${#window[@]} -gt 5 ]; then
                window=("${window[@]:1:5}")
            fi
            sum=0
            for v in "${window[@]}"; do
                sum=$((sum + v))
            done
            avg=$((sum / ${#window[@]}))
            echo "$avg"
        fi
    fi
done
EOF
    chmod +x /oracle/process_configs_oracle.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
