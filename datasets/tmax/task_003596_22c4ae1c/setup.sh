#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip coreutils bash
pip3 install pytest

mkdir -p /home/user

# Create the buggy script
cat << 'EOF' > /home/user/log_processor.sh
#!/bin/bash
declare -a STATE_HISTORY

parse_message() {
    local msg="$1"
    if [[ "$msg" == *"{{"* ]]; then
        if [[ "$msg" == *"}}"* ]]; then
            # Valid message, extract data
            extracted="${msg#*\{\{}"
            extracted="${extracted%%\}\}*}"
            echo "Processed: $extracted"
        else
            # BUG: Infinite recursion on malformed input
            STATE_HISTORY+=("$msg")
            parse_message "$msg"
        fi
    else
        echo "Ignored: $msg"
    fi
}

# Entry point
parse_message "$1"
EOF
chmod +x /home/user/log_processor.sh

# Make a backup for diffing later
cp /home/user/log_processor.sh /home/user/log_processor.sh.orig

# Create the simulated memory dump
dd if=/dev/urandom of=/home/user/service_mem.dump bs=1K count=1024 2>/dev/null

# Inject the leaked string 5000 times to simulate the unbounded array memory leak
LEAKED_STRING="[SESSION_4815] {{DATA_FRAG_992_UNMATCHED"
for i in {1..5000}; do
    echo -n "$LEAKED_STRING" >> /home/user/service_mem.dump
    echo -ne '\x00' >> /home/user/service_mem.dump
done

# Append a bit more binary gibberish
dd if=/dev/urandom bs=1K count=100 >> /home/user/service_mem.dump 2>/dev/null

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
