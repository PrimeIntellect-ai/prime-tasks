#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    awk 'BEGIN {
        for(i=1; i<=5000; i++) {
            val = 1000000000 + (i % 7)
            print val
        }
    }' > /home/user/mem_stats.log

    cat << 'EOF' > /home/user/calc_variance.sh
#!/bin/bash
awk '{
    sum += $1
    sumsq += $1 * $1
    n++
    var = (sumsq / n) - (sum / n) * (sum / n)
    print n, var
}' "$1"
EOF
    chmod +x /home/user/calc_variance.sh

    chmod -R 777 /home/user
