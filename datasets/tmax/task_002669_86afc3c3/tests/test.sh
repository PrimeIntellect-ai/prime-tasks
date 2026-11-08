#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess


def test_jaccard_similarity_and_output():
    agent_file = "/home/user/top_100_anomalies.csv"
    assert os.path.exists(agent_file), f"Agent output file missing at {agent_file}"
    assert os.path.isfile(agent_file), f"Agent output is not a regular file: {agent_file}"

    # Generate truth dynamically using the specified procedure.
    bash_script = r'''set -o pipefail
grep -v "|DEBUG_" /home/user/raw_logs.txt | \
sort -t'|' -k2,2 -k1,1 | \
awk -F'|' '
  BEGIN { OFS="\t" }
  {
    if ($2 != last_user) {
      if (last_user != "") {
        print last_user, acts
      }
      last_user = $2
      last_act = $3
      acts = $3
    } else {
      if ($3 != last_act) {
        acts = acts "," $3
        last_act = $3
      }
    }
  }
  END {
    if (last_user != "") print last_user, acts
  }
' | /app/anomaly_scorer | sort -k2,2nr -k1,1 | head -n 100 | tr '\t' ','
'''

    result = subprocess.run(
        ["/bin/bash", "-c", bash_script],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Failed to compute truth: {result.stderr}"

    truth_lines = result.stdout.splitlines()
    truth_users = set()
    for line in truth_lines:
        if line:
            truth_users.add(line.split(',')[0])

    with open(agent_file, 'r', newline='') as f:
        agent_text = f.read()
    agent_lines = agent_text.splitlines()

    agent_users = set()
    for line in agent_lines:
        parts = line.strip().split(',')
        if parts:
            agent_users.add(parts[0])

    # Preserve the original overlap assertion.
    intersection = len(truth_users.intersection(agent_users))
    union = len(truth_users.union(agent_users))
    jaccard = intersection / union if union > 0 else 0
    assert jaccard >= 0.99, (
        f"Jaccard similarity {jaccard:.4f} is less than threshold 0.99. "
        f"Intersection: {intersection}, Union: {union}."
    )

    # Enforce the requested row count, CSV shape, uniqueness, scores, and ordering.
    assert len(agent_lines) == 100, f"Expected exactly 100 rows, found {len(agent_lines)}"
    row_pattern = re.compile(r'^U[0-9]{4},[0-9]+\.[0-9]{4}$')
    for number, line in enumerate(agent_lines, 1):
        assert row_pattern.fullmatch(line), f"Malformed row {number}: {line!r}"
    assert len(agent_users) == 100, "Output contains duplicate UserIDs"
    assert agent_lines == truth_lines, "Output rows, scores, or ordering differ from the definitive result"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
