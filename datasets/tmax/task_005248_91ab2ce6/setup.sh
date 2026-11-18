#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/expr_valid
    echo "A = B + C" > /home/user/expr_valid/A.expr
    echo "B = D * 2" > /home/user/expr_valid/B.expr
    echo "C = D + 3" > /home/user/expr_valid/C.expr
    echo "D = 10" > /home/user/expr_valid/D.expr

    mkdir -p /home/user/expr_invalid
    echo "X = Y + Z + W" > /home/user/expr_invalid/X.expr
    echo "Y = V * 2" > /home/user/expr_invalid/Y.expr
    echo "Z = V + 1" > /home/user/expr_invalid/Z.expr
    echo "W = V - 1" > /home/user/expr_invalid/W.expr
    echo "V = 5" > /home/user/expr_invalid/V.expr

    mkdir -p /home/user/expr_cycle
    echo "P = Q + 1" > /home/user/expr_cycle/P.expr
    echo "Q = R + 1" > /home/user/expr_cycle/Q.expr
    echo "R = P + 1" > /home/user/expr_cycle/R.expr

    chmod -R 777 /home/user
