#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git build-essential gawk coreutils grep sed
    pip3 install pytest

    # Create tinysupervisor package
    mkdir -p /app/tinysupervisor-1.0
    cat << 'EOF' > /app/tinysupervisor-1.0/tinysupervisor
#!/bin/bash
echo "tinysupervisor running"
EOF
    chmod +x /app/tinysupervisor-1.0/tinysupervisor

    cat << 'EOF' > /app/tinysupervisor-1.0/Makefile
all:
	@echo "Built"

install:
	mkdir -p $(PREFX)/bin
	cp tinysupervisor $(PREFX)/bin/
	chmod +x $(PREFX)/bin/tinysupervisor
EOF

    # Create oracle script
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/validate_manifest_oracle.sh
#!/bin/bash
while IFS= read -r line || [ -n "$line" ]; do
    num_fields=$(echo "$line" | awk -F',' '{print NF}')
    if [ "$num_fields" -ne 4 ]; then
        echo "[INVALID] $line"
        continue
    fi

    service_name=$(echo "$line" | awk -F',' '{print $1}')
    replicas=$(echo "$line" | awk -F',' '{print $2}')
    port=$(echo "$line" | awk -F',' '{print $3}')
    image=$(echo "$line" | awk -F',' '{print $4}')

    if ! [[ "$service_name" =~ ^svc-[a-z0-9]{1,10}$ ]]; then
        echo "[INVALID] $line"
        continue
    fi
    if ! [[ "$replicas" =~ ^[1-9]$ ]]; then
        echo "[INVALID] $line"
        continue
    fi
    if ! [[ "$port" =~ ^80[0-9]{2}$ ]]; then
        echo "[INVALID] $line"
        continue
    fi
    if ! [[ "$image" =~ ^registry\.local/[a-z0-9]{1,20}:v[0-9]$ ]]; then
        echo "[INVALID] $line"
        continue
    fi

    echo "[VALID] ${service_name}:${port}"
done
EOF
    chmod +x /opt/oracle/validate_manifest_oracle.sh

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
