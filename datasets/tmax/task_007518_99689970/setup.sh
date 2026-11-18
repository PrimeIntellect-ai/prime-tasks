#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/loc

    cat << 'EOF' > /home/user/loc/en_base.txt
ERR_001=Equation [eq_name] lacks variable [x].
ERR_002=Matrix determinant is zero.
ERR_003=Value [val] exceeds limit [max].
ERR_004=Algorithm [alg] failed at step [step_id] with code [err_code].
ERR_005=Convergence not reached after [n] iterations.
ERR_006=Syntax error in expression [expr].
EOF

    cat << 'EOF' > /home/user/loc/fr_raw.txt
ERR_002=Le déterminant de la matrice est zéro.
ERR_001=L'équation [eq_name] manque de variable [x].
ERR_001=L'équation [eq_name] manque de variable.
ERR_003=La valeur [val] dépasse la limite.
ERR_004=L'algorithme [alg] a échoué à l'étape [step_id] avec le code [err_code].
ERR_002=Le déterminant de la matrice est zéro.
ERR_006=Erreur de syntaxe dans l'expression [expr].
ERR_009=Erreur inconnue.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
