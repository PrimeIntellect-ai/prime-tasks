#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    mkdir -p /app/bio-spectral-v1.0
    mkdir -p /home/user

    cat << 'EOF' > /app/bio-spectral-v1.0/run_spectral.sh
#!/bin/bash
seq=$1
echo "$seq" | awk 'BEGIN{FS=""}{for(i=1;i<=NF;i++) {if($i=="A") print 1; else if($i=="C") print 2; else if($i=="G") print 3; else print 4}}' | awk -f /app/bio-spectral-v1.0/detrend.awk | awk -f /app/bio-spectral-v1.0/fft.awk
EOF
    chmod +x /app/bio-spectral-v1.0/run_spectral.sh

    cat << 'EOF' > /app/bio-spectral-v1.0/detrend.awk
{
    val[NR] = $1
    sum += $1
    sum_sq += $1*$1
    N = NR
}
END {
    var = (sum_sq / N) - ((sum / N) * (sum / N))
    # BUG: var can be 0, causing division by zero in sqrt(var)
    for(i=1; i<=N; i++) {
        print (val[i] - (sum/N)) / sqrt(var)
    }
}
EOF

    cat << 'EOF' > /app/bio-spectral-v1.0/fft.awk
# Simplified mock spectral score (sum of absolute differences)
{
    val[NR] = $1
    N=NR
}
END {
    score = 0
    for(i=2; i<=N; i++) {
        score += (val[i] - val[i-1])^2
    }
    print score
}
EOF

    cat << 'EOF' > /home/user/sequences.fasta
>seq1
ACGTACGTACGTACGTACGTACGT
>seq2
AAAAAAAAAAAAAAAAAAAAAAAA
>seq3
AGCTAGCTAGCTAGCTAGCTAGCT
>seq4
GGCGCGCGCGCGCGCGCGCGCGCG
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
