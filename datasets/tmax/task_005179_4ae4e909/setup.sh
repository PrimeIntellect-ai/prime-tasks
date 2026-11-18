#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip parallel
pip3 install pytest

mkdir -p /home/user/raw_configs

generate_config() {
    local file=$1
    local role=$2
    local tier=$3
    local region=$4
    local noise=$5

    cat <<EOF > "$file"
# Server Configuration Snapshot
# Generated automatically

EOF

    if [ "$noise" -eq 1 ]; then
        echo "  ROLE = $role  " >> "$file"
        echo "TIER=$tier" >> "$file"
        echo "  region =   $region" >> "$file"
    elif [ "$noise" -eq 2 ]; then
        echo "Role=$role" >> "$file"
        echo "# tier is next" >> "$file"
        echo "   Tier = $tier" >> "$file"
        echo "Region = $region" >> "$file"
    else
        echo "role=$role" >> "$file"
        echo "tier=$tier" >> "$file"
        echo "region=$region" >> "$file"
    fi

    echo "max_connections = 100" >> "$file"
    echo "timeout = 30" >> "$file"
}

# Create 25 Web/Frontend/US-East
for i in $(seq 1 25); do
    generate_config "/home/user/raw_configs/server_web_${i}.conf" "WEB" "FrontEnd" "US-East" $((i % 3))
done

# Create 15 DB/Backend/US-West
for i in $(seq 1 15); do
    generate_config "/home/user/raw_configs/server_db_${i}.conf" "db" "BACKEND" "us-west" $((i % 3))
done

# Create 10 Cache/Backend/US-East (missing region on last 5)
for i in $(seq 1 5); do
    generate_config "/home/user/raw_configs/server_cache_${i}.conf" "Cache" "Backend" "US-East" $((i % 3))
done
for i in $(seq 6 10); do
    file="/home/user/raw_configs/server_cache_${i}.conf"
    echo "# Server Configuration" > "$file"
    echo "role = Cache" >> "$file"
    echo " tier = Backend " >> "$file"
    echo "timeout=10" >> "$file"
done

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
