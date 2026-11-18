#!/bin/bash
set -e
mkdir -p /logs/verifier

reward=0

if [ -f /home/user/forged_tokens.txt ] && [ ! -L /home/user/forged_tokens.txt ]; then
    if verifier_output="$(python3 /app/verifier.py 2>&1)"; then
        if SCORE_OUTPUT="$verifier_output" python3 - <<'PY'
import math
import os
import sys

lines = [line.strip() for line in os.environ.get("SCORE_OUTPUT", "").splitlines() if line.strip()]
if not lines:
    sys.exit(1)

try:
    score = float(lines[-1])
except ValueError:
    sys.exit(1)

sys.exit(0 if math.isfinite(score) and score >= 0.95 else 1)
PY
        then
            reward=1
        fi
    fi
fi

echo "$reward" > /logs/verifier/reward.txt
