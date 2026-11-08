#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/geo_project

    cat << 'EOF' > /home/user/geo_project/geo_math.py
import math

def compute_chord_length(theta):
    # Calculates the straight-line distance between two points on a unit circle
    # separated by angle theta.
    # Users report this returns 0.0 for small theta!
    val = 1.0 - math.cos(theta)
    return math.sqrt(2.0 * val)
EOF

    cat << 'EOF' > /home/user/geo_project/verify.py
import math
from geo_math import compute_chord_length

def verify():
    test_vals = [1e-9, 1e-8, 1e-7, 1.0, 3.14]
    results = []

    # Check if assertions exist by testing invalid types
    try:
        compute_chord_length("string")
        print("Missing type assertion.")
        exit(1)
    except AssertionError as e:
        if "theta must be a float" not in str(e):
            print("Incorrect type assertion message.")
            exit(1)
    except Exception:
        print("Missing or incorrect type assertion.")
        exit(1)

    try:
        compute_chord_length(-1.0)
        print("Missing value assertion.")
        exit(1)
    except AssertionError as e:
        if "theta must be non-negative" not in str(e):
            print("Incorrect value assertion message.")
            exit(1)
    except Exception:
        print("Missing or incorrect value assertion.")
        exit(1)

    for t in test_vals:
        res = compute_chord_length(t)
        expected = 2.0 * math.sin(t / 2.0)

        if not math.isclose(res, expected, rel_tol=1e-5, abs_tol=1e-12):
            print(f"Failed for {t}. Got {res}, expected {expected}")
            exit(1)

        results.append(res)

    with open("/home/user/geo_project/success.txt", "w") as f:
        for r in results:
            f.write(f"{r:.12e}\n")
    print("Verification passed.")

if __name__ == "__main__":
    verify()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
