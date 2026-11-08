#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gawk locales
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/locales_wide.csv
msg_id,en,fr,es,zh
btn_sum,Sum ∑,Somme ∑,Suma ∑,总和 ∑
btn_sqrt,Square Root √,Racine carrée √,Raíz cuadrada √,平方根 √
btn_approx,Approx ≈,Environ ≈,Aproximadamente ≈,近似 ≈
btn_inf,Infinity ∞,Infini ∞,Infinito ∞,无穷 ∞
btn_pm,Plus-Minus ±,Plus-Moins ±,Más-Menos ±,正负 ±
EOF

    chmod -R 777 /home/user
