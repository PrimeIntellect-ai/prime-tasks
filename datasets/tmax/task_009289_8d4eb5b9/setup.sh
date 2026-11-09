#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/sim_project
    cd /home/user/sim_project

    cat << 'EOF' > integrator.sh
#!/bin/bash
k=$1
y=100
t=0
dt=2.0
while [ $(echo "$t < 10" | bc -l) -eq 1 ]; do
    y=$(echo "$y - $k * $y * $dt" | bc -l)
    t=$(echo "$t + $dt" | bc -l)
done
printf "%.4f\n" "$y"
EOF
    chmod +x integrator.sh

    gawk 'BEGIN {srand(42); for(i=1; i<=100; i++) printf "%.2f\n", 0.5 + rand()*1.5}' > k_values.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
