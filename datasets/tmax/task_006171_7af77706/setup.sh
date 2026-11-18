#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    mkdir -p /home/user/app
    cat << 'EOF' > /home/user/app/simulate_ode.sh
#!/bin/bash
h=${1:-0.1}
awk -v h="$h" 'BEGIN {
    y = 1.0;
    for(t=0; t<=2; t+=h) {
        printf "%.6f %.6f\n", t, y;
        y = y + h * (-100 * y + sin(t));
    }
}'
EOF
    chmod +x /home/user/app/simulate_ode.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
