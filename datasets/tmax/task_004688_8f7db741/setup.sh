#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gnuplot bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sim.sh
#!/bin/bash
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <X> <Y>"
    exit 1
fi
x=$1
y=$2
# Peak is at X=2.5, Y=3.5, Z=100.00
awk -v x="$x" -v y="$y" 'BEGIN { printf "%.2f\n", 100 - (x-2.5)^2 - (y-3.5)^2 }'
EOF
    chmod +x /home/user/sim.sh

    chmod -R 777 /home/user
