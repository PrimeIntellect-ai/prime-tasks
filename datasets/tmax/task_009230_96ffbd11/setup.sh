#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip locales gawk coreutils
    pip3 install pytest

    # Generate the locale needed for the bug to manifest
    locale-gen de_DE.UTF-8

    mkdir -p /home/user

    cat << 'EOF' > /home/user/readings.csv
s1,0.12
s2,1.55
s3,2.99
s4,0.85
s5,3.50
s6,1.20
s7,4.10
EOF

    cat << 'EOF' > /home/user/priors.csv
s1,0.1
s2,0.8
s3,0.7
s4,0.5
s5,0.9
s6,0.95
s7,0.4
EOF

    cat << 'EOF' > /home/user/etl.sh
#!/bin/bash
# ETL Pipeline for Bayesian Anomaly Detection
export LC_NUMERIC="de_DE.UTF-8" # Misconfiguration causing float parsing issues in awk

join -t, <(sort -t, -k1,1 /home/user/readings.csv) <(sort -t, -k1,1 /home/user/priors.csv) | \
awk -F, '{
    # $1=id, $2=value, $3=prior
    likelihood = 1 - exp(-$2);
    posterior = likelihood * $3;
    if (posterior > 0.5) {
        printf "%s %.6f\n", $1, posterior;
    }
}' > /home/user/anomalies.txt
EOF

    chmod +x /home/user/etl.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
