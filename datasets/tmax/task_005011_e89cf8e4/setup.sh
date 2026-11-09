#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential wget gawk
    pip3 install pytest

    mkdir -p /app
    cd /app
    wget https://ftp.gnu.org/gnu/datamash/datamash-1.8.tar.gz
    tar -xzf datamash-1.8.tar.gz
    rm datamash-1.8.tar.gz

    # Perturb Makefile.in
    sed -i '1s/^/CC = \/bin\/false\n/' /app/datamash-1.8/Makefile.in

    # Create oracle script
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/eval_tracker_oracle.sh
#!/bin/bash
awk -F',' '$5 != "" {
    exp=$2;
    time_sum[exp]+=$3;
    count[exp]++;
    if($4==$5) correct[exp]++;
}
END {
    for (e in count) {
        avg_time = time_sum[e] / count[e];
        acc = correct[e] / count[e];
        printf "%s,%.4f,%.4f\n", e, avg_time, acc;
    }
}' "$1" | sort -t',' -k1,1
EOF
    chmod +x /opt/oracle/eval_tracker_oracle.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
