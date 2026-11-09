#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_math

    printf "1,000\r\n50\r\n2,500\r\n12\r\n300\r\n" > /home/user/legacy_math/inputs.txt

    echo "3" > /home/user/multiplier.conf

    cat << 'EOF' > /home/user/legacy_math/calc.sh
#!/bin/bash

# Initialize sum
echo 0 > /home/user/legacy_math/sum.txt

# Read multiplier
MULTIPLIER=$(cat "$CONF_DIR/multiplier.conf")

process_number() {
    local raw_val="$1"
    # BUG 2: raw_val has commas and \r, causing bash arithmetic to fail
    local val=$raw_val 

    local squared=$(( val * val ))
    local final_val=$(( squared * MULTIPLIER ))

    # BUG 3: Race condition
    local current_sum=$(cat /home/user/legacy_math/sum.txt)
    local new_sum=$(( current_sum + final_val ))
    echo $new_sum > /home/user/legacy_math/sum.txt
}

while read -r line; do
    if [ -n "$line" ]; then
        process_number "$line" &
    fi
done < /home/user/legacy_math/inputs.txt

wait

echo "Final sum is: $(cat /home/user/legacy_math/sum.txt)"
EOF

    chmod +x /home/user/legacy_math/calc.sh

    chown -R user:user /home/user
    chmod -R 777 /home/user
