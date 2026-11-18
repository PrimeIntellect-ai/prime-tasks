#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make valgrind
    pip3 install pytest hypothesis numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/math_port

    cat << 'EOF' > /home/user/math_port/det_calc.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main() {
    int n;
    if (scanf("%d", &n) != 1) return 1;

    double **matrix = (double **)malloc(n * sizeof(double *));
    for (int i = 0; i < n; i++) {
        matrix[i] = (double *)malloc(n * sizeof(double));
        for (int j = 0; j < n; j++) {
            if (scanf("%lf", &matrix[i][j]) != 1) return 1;
        }
    }

    double det = 1.0;
    for (int i = 0; i < n; i++) {
        // Find pivot
        int pivot = i;
        for (int j = i + 1; j < n; j++) {
            if (fabs(matrix[j][i]) > fabs(matrix[pivot][i])) {
                pivot = j;
            }
        }

        // Swap rows
        if (pivot != i) {
            double *temp = matrix[i];
            matrix[i] = matrix[pivot];
            matrix[pivot] = temp;
            // BUG: Missing det = -det;
        }

        if (fabs(matrix[i][i]) < 1e-9) {
            det = 0.0;
            break;
        }

        det *= matrix[i][i];

        // Eliminate
        for (int j = i + 1; j < n; j++) {
            double factor = matrix[j][i] / matrix[i][i];
            for (int k = i; k < n; k++) {
                matrix[j][k] -= factor * matrix[i][k];
            }
        }
    }

    printf("%.6f\n", det);

    // BUG: Missing free loop
    // for(int i=0; i<n; i++) free(matrix[i]);
    // free(matrix);

    return 0;
}
EOF

    cat << 'EOF' > /home/user/math_port/verify_props.py
import subprocess
import numpy as np
from hypothesis import given, settings
from hypothesis.strategies import floats
import hypothesis.extra.numpy as hnp
import sys

def run_c_tool(matrix, check_valgrind=False):
    n = matrix.shape[0]
    input_str = f"{n}\n" + "\n".join(" ".join(str(x) for x in row) for row in matrix) + "\n"

    cmd = ["./det_calc"]
    if check_valgrind:
        cmd = ["valgrind", "--leak-check=full", "--error-exitcode=1"] + cmd

    result = subprocess.run(cmd, input=input_str.encode(), capture_output=True)
    if check_valgrind and result.returncode != 0:
        print("Valgrind reported a memory leak!")
        sys.exit(1)

    return float(result.stdout.decode().strip())

@settings(max_examples=20, deadline=None)
@given(
    hnp.arrays(dtype=np.float64, shape=(4, 4), elements=floats(min_value=-10, max_value=10)),
    hnp.arrays(dtype=np.float64, shape=(4, 4), elements=floats(min_value=-10, max_value=10))
)
def test_determinant_properties(A, B):
    # Check memory leaks on a small test
    run_c_tool(A, check_valgrind=True)

    det_A = run_c_tool(A)
    det_B = run_c_tool(B)
    det_AB = run_c_tool(np.dot(A, B))

    # Check multiplicative property
    assert np.isclose(det_AB, det_A * det_B, rtol=1e-3, atol=1e-3), f"Property failed: det(AB)={det_AB}, det(A)*det(B)={det_A * det_B}"

if __name__ == "__main__":
    try:
        test_determinant_properties()
        with open("/home/user/math_port/verification.log", "w") as f:
            f.write("SUCCESS\n")
        print("All tests passed.")
    except Exception as e:
        print(f"Tests failed: {e}")
        sys.exit(1)
EOF

    chmod -R 777 /home/user
