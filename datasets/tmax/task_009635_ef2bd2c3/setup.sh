#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc build-essential
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user/repo

cat << 'EOF' > /tmp/setup.sh
#!/bin/bash
mkdir -p /home/user/repo

create_artifact() {
    local file="/home/user/repo/$1"
    local ts=$2
    local payload="$3"
    local bad_magic=$4
    local bad_chk=$5

    local magic="ARTF"
    if [ "$bad_magic" == "1" ]; then
        magic="BART"
    fi

    local payload_size=${#payload}

    local chk=0
    for (( i=0; i<${#payload}; i++ )); do
        local char=$(printf "%d" "'${payload:$i:1}")
        chk=$(( (chk + char) % 256 ))
    done

    if [ "$bad_chk" == "1" ]; then
        chk=$(( (chk + 1) % 256 ))
    fi

    echo -n "$magic" > "$file"
    printf "%b" "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' $((ts & 255)) $(( (ts >> 8) & 255 )) $(( (ts >> 16) & 255 )) $(( (ts >> 24) & 255 )))" >> "$file"
    printf "%b" "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' $((payload_size & 255)) $(( (payload_size >> 8) & 255 )) $(( (payload_size >> 16) & 255 )) $(( (payload_size >> 24) & 255 )))" >> "$file"
    echo -n "$payload" >> "$file"
    printf "%b" "$(printf '\\x%02x' $chk)" >> "$file"
}

create_artifact "alpha.bin" 1700000005 "TestDataOne" 0 0
create_artifact "beta.bin" 1600000000 "OldData" 0 0
create_artifact "gamma.bin" 1700000000 "ExactTime" 0 0
create_artifact "delta.bin" 1750000000 "BadMagic" 1 0
create_artifact "epsilon.bin" 1710000000 "BadChecksum" 0 1
create_artifact "zeta.bin" 1720000000 "TruncatedData" 0 0
truncate -s -2 /home/user/repo/zeta.bin
create_artifact "omega.bin" 1725000000 "LastValidData" 0 0
EOF

bash /tmp/setup.sh
rm /tmp/setup.sh

chmod -R 777 /home/user
