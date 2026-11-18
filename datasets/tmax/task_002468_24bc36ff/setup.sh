#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk findutils coreutils
pip3 install pytest

mkdir -p /home/user/simulation_runs

cat << 'EOF' > /home/user/setup_data.sh
#!/bin/bash
mkdir -p /home/user/simulation_runs

# Generate deterministic data: Base function E(t) = 3 * t^2. Integral from 0 to 10 is 1000.
# We will create 50 files with slight, reproducible variations.
awk 'BEGIN {
    srand(12345);
    for (run=1; run<=50; run++) {
        file = sprintf("/home/user/simulation_runs/run_%d.csv", run);
        print "time,energy" > file;
        t = 0;
        e = 0;
        print t "," e > file;

        # multiplier to create slight variance between runs (~0.95 to 1.05)
        run_noise = 0.95 + (rand() * 0.1); 

        while (t < 10) {
            dt = 0.05 + (rand() * 0.15); # Variable time step between 0.05 and 0.20
            t += dt;
            if (t > 10) t = 10;
            e = 3 * t * t * run_noise;
            printf "%.4f,%.4f\n", t, e > file;
        }
        close(file);
    }
}'
EOF
chmod +x /home/user/setup_data.sh
/home/user/setup_data.sh

# Create the broken integrate.sh
cat << 'EOF' > /home/user/integrate.sh
#!/bin/bash
# BROKEN INTEGRATOR
awk -F, 'NR>1 {sum += $2 * 0.1} END {print sum}' "$1"
EOF
chmod +x /home/user/integrate.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
