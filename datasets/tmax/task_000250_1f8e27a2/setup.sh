#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    awk 'BEGIN { srand(42); for(i=1;i<=5000;i++) printf "%.6f\n", (rand()*4)-2 }' > /home/user/samples.txt

    rm -f /home/user/truth_convergence.log
    for N in 1000 2000 3000 4000 5000; do
        head -n $N /home/user/samples.txt > /tmp/test_$N.txt
        split -l 1000 /tmp/test_$N.txt /tmp/truth_chunk_$N_

        > /tmp/truth_partials_$N.txt
        for f in $(ls /tmp/truth_chunk_$N_* | sort); do
            awk '{s+=exp(-$1*$1/2)} END {printf "%.15f\n", s}' $f >> /tmp/truth_partials_$N.txt
        done

        FINAL_SUM=$(awk '{s+=$1} END {printf "%.15f\n", s}' /tmp/truth_partials_$N.txt)
        echo "$N $FINAL_SUM" >> /home/user/truth_convergence.log
    done

    chmod -R 777 /home/user
