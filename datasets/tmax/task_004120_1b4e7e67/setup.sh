#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc
    pip3 install pytest

    mkdir -p /app/bash-fasta-density-1.0/bin
    mkdir -p /opt/oracle

    cat << 'EOF' > /app/bash-fasta-density-1.0/bin/calc_density.sh
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: $0 <fasta_file>"
    exit 1
fi

compute_gc() {
    seq="$1"
    gc=$(echo "$seq" | grep -o -i "[GC]" | wc -l)
    total=$(echo "$seq" | grep -o -i "[ACGT]" | wc -l)
    if [ "$total" -eq 0 ]; then
        echo "0"
    else
        echo "scale=4; $gc / $total" | bc
    fi
}

grep -v "^>" "$1" | xargs -P 4 -I {} bash -c 'compute_gc "{}"'
EOF
    chmod +x /app/bash-fasta-density-1.0/bin/calc_density.sh

    cat << 'EOF' > /opt/oracle/oracle_run_density.sh
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: $0 <fasta_file>"
    exit 1
fi

compute_gc() {
    seq="$1"
    gc=$(echo "$seq" | grep -o -i "[GC]" | wc -l)
    total=$(echo "$seq" | grep -o -i "[ACGT]" | wc -l)
    if [ "$total" -eq 0 ]; then
        echo "0"
    else
        echo "scale=4; $gc / $total" | bc
    fi
}
export -f compute_gc

grep -v "^>" "$1" | xargs -P 4 -I {} bash -c 'compute_gc "{}"'
EOF
    chmod +x /opt/oracle/oracle_run_density.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
