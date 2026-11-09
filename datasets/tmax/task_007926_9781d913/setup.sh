#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/calc_energy.sh
#!/bin/bash
# Calculates total signal energy via adaptive numerical integration
# Function: f(x) = exp(-x^2/2) from x=-5 to 5

N=2
old_val=100.0
iteration=0

while [ $iteration -lt 50 ]; do
    dx=$(echo "scale=6; 10 / $N" | bc -l)

    val=$(awk -v N="$N" -v dx="$dx" 'BEGIN {
        sum=0
        for(i=0; i<=N; i++){
            x = -5 + i*dx
            sum += dx * exp(-x*x/2)
        }
        print sum
    }')

    # absolute difference
    diff=$(echo "$val - $old_val" | bc -l | sed 's/^-//')

    # check convergence
    if [ $(echo "$diff < 0.0001" | bc -l) -eq 1 ]; then
        echo "Converged: $val" > /home/user/energy.log
        exit 0
    fi

    old_val=$val

    # Adaptive step size (Flawed logic)
    # The error is roughly proportional to 1/N. 
    # The script mistakenly assumes N should decrease to reduce error.
    factor=$(echo "scale=4; sqrt(0.0001 / $diff)" | bc -l)
    N=$(echo "$N * $factor / 1" | bc) # division by 1 to truncate to integer

    iteration=$((iteration+1))
done

echo "Failed to converge" > /home/user/energy.log
exit 1
EOF
    chmod +x /home/user/calc_energy.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
