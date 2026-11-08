#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go git
    pip3 install pytest pyyaml

    # Setup vendored package
    mkdir -p /app/vendor
    git clone --depth 1 --branch v3.0.1 https://github.com/go-yaml/yaml.git /app/vendor/yaml.v3
    # Apply perturbation
    sed -i 's/return unmarshal(in, out, false)/panic("TODO: implement")\n\t\/\/ return unmarshal(in, out, false)/' /app/vendor/yaml.v3/yaml.go

    # Setup oracle
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/lb_decision_oracle
#!/usr/bin/env python3
import sys
import yaml

def main():
    try:
        data = yaml.safe_load(sys.stdin)
    except Exception:
        sys.exit(1)

    vms = data.get('vms', [])
    if not vms:
        print("503 Service Unavailable")
        return

    valid_vms = [vm for vm in vms if vm.get('status') == 'online' and vm.get('cpu', 100.0) < 80.0]

    if not valid_vms:
        print("503 Service Unavailable")
        return

    valid_vms.sort(key=lambda x: (x.get('cpu', 100.0), x.get('id', '')))
    best_vm = valid_vms[0]
    print(f"ROUTE: {best_vm['id']}")

if __name__ == '__main__':
    main()
EOF
    chmod +x /opt/oracle/lb_decision_oracle

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
