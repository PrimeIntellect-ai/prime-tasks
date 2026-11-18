#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/sparse_poly_pr
    cat << 'EOF' > /home/user/sparse_poly_pr/sparse_poly.py
class SparsePolynomial:
    def __init__(self, coeffs=None):
        self.coeffs = coeffs if coeffs is not None else {}
        self._cleanup()

    def _cleanup(self):
        self.coeffs = {k: v for k, v in self.coeffs.items() if v != 0}

    def __add__(self, other):
        res = self.coeffs.copy()
        for k, v in other.coeffs.items():
            res[k] = res.get(k, 0) + v
        return SparsePolynomial(res)

    def __mul__(self, other):
        res = {}
        for k1, v1 in self.coeffs.items():
            for k2, v2 in other.coeffs.items():
                # BUG 1: overwriting instead of accumulating
                # BUG 2: adding coefficients instead of multiplying
                res[k1 + k2] = v1 + v2
        return SparsePolynomial(res)

    def __eq__(self, other):
        return self.coeffs == other.coeffs
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
