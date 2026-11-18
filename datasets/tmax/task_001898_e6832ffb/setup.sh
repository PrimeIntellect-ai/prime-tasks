#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mc_results.fasta
>model_alpha
1.5 1.6 1.4 1.5
>model_beta
2.1 2.1 2.1 2.1
>model_gamma
3.0 3.1 2.9 3.0
>model_delta
0.0 0.0 0.0 0.0
>model_epsilon
5.5 5.4 5.6 5.5
>model_zeta
-1.2 -1.2 -1.2 -1.2
>model_eta
4.1 4.2 4.0 4.2 4.1
>model_theta
0.5 0.5 0.5 0.5
EOF

    chmod -R 777 /home/user
