#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy

mkdir -p /home/user/ops_triage/bad_deps

cat << 'EOF' > /home/user/ops_triage/bad_deps/numpy.py
class ImportError(Exception): pass
raise Exception("Fatal: Incompatible rogue numpy module loaded due to PYTHONPATH conflict!")
EOF

cat << 'EOF' > /home/user/ops_triage/run_pipeline.sh
#!/bin/bash
# Adding local deps (this is causing the conflict)
export PYTHONPATH="/home/user/ops_triage/bad_deps:$PYTHONPATH"
python3 /home/user/ops_triage/model_optimizer.py
EOF
chmod +x /home/user/ops_triage/run_pipeline.sh

cat << 'EOF' > /home/user/ops_triage/model_optimizer.py
import numpy as np
import sys
import json

def objective(x):
    # Parabola opening upwards, minimum at x = -2.0
    return x**2 + 4*x + 4

def gradient(x):
    return 2*x + 4

def optimize():
    x = 10.0
    learning_rate = 0.1
    max_iterations = 1000

    for i in range(max_iterations):
        grad = gradient(x)

        # BUG: The update rule is adding the gradient instead of subtracting it.
        # This causes the algorithm to diverge.
        x += grad * learning_rate

        if abs(grad) < 1e-5:
            return x

    raise RuntimeError(f"Failed to converge within {max_iterations} iterations. Final x={x}, grad={grad}")

if __name__ == "__main__":
    try:
        optimal_x = optimize()
        output = {"optimal_x": round(optimal_x, 5)}
        with open("/home/user/ops_triage/optimized_weights.json", "w") as f:
            json.dump(output, f)
        print("Pipeline succeeded.")
    except Exception as e:
        print(f"Pipeline failed: {e}", file=sys.stderr)
        sys.exit(1)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
