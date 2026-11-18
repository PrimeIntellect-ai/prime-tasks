#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sim_euler.sh
#!/bin/bash
dt=$1
t=0
y=1
echo "Initializing Euler integrator..."
echo "Starting simulation with step size $dt"
# Simple dy/dt = y Euler integration
while [ $(echo "$t < 1.0" | bc -l) -eq 1 ]; do
    y=$(echo "$y + $y * $dt" | bc -l)
    t=$(echo "$t + $dt" | bc -l)
done
echo "Integration complete."
echo "Final Output: t=$t, y=$y"
EOF

    chmod +x /home/user/sim_euler.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
