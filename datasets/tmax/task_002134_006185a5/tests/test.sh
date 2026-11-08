#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import json
import tempfile
import subprocess
import csv
import uuid
import pytest


def test_classifier_script():
    # 1. Find the agent's script
    possible_scripts = glob.glob("/home/user/classify.*")
    assert possible_scripts, "No classify script found at /home/user/classify.*"
    script_path = possible_scripts[0]

    # 2. Build the same behavioral corpus only after the agent has finished.
    workflows = [
        ("clean", [
            {"source": "N1", "target": "N2"},
            {"source": "N2", "target": "N3"},
            {"source": "N3", "target": "N4"},
            {"source": "N4", "target": "N5"},
            {"source": "N5", "target": "N6"},
            {"source": "N6", "target": "N7"},
        ]),
        ("clean", [
            {"source": "A", "target": "B"},
            {"source": "A", "target": "C"},
        ]),
        ("evil", [
            {"source": "N1", "target": "N2"},
            {"source": "N2", "target": "N3"},
            {"source": "N3", "target": "N4"},
            {"source": "N4", "target": "N5"},
            {"source": "N5", "target": "N6"},
            {"source": "N6", "target": "N7"},
            {"source": "N7", "target": "N8"},
        ]),
        ("evil", [
            {"source": "A", "target": "B"},
            {"source": "B", "target": "C"},
            {"source": "C", "target": "A"},
        ]),
    ]

    with tempfile.TemporaryDirectory() as tmp_input_dir:
        clean_files = []
        evil_files = []
        for expected, edges in workflows:
            filename = f"workflow_{uuid.uuid4().hex}.json"
            with open(os.path.join(tmp_input_dir, filename), "w", encoding="utf-8") as f:
                json.dump(edges, f)
            if expected == "clean":
                clean_files.append(filename)
            else:
                evil_files.append(filename)

        output_csv = os.path.join(tmp_input_dir, "results.csv")

        # 3. Run the agent's script
        if script_path.endswith('.py') and not os.access(script_path, os.X_OK):
            cmd = ["python3", script_path]
        elif script_path.endswith('.js') and not os.access(script_path, os.X_OK):
            cmd = ["node", script_path]
        else:
            cmd = [script_path]
        cmd.extend([tmp_input_dir, output_csv])

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        except Exception as e:
            pytest.fail(f"Failed to execute the classification script: {e}")

        assert result.returncode == 0, (
            f"Script failed with return code {result.returncode}.\n"
            f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
        )
        assert os.path.exists(output_csv), f"Output CSV not found at {output_csv}"

        # 4. Parse the output CSV
        results = {}
        with open(output_csv, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            header = next(reader, None)
            assert header == ['filename', 'status'], (
                f"Expected CSV header ['filename', 'status'], got {header}"
            )
            for row in reader:
                if len(row) == 2:
                    results[row[0]] = row[1].strip().lower()

        # 5. Verify results
        clean_failures = [f for f in clean_files if results.get(f) != 'clean']
        evil_failures = [f for f in evil_files if results.get(f) != 'evil']

        error_msg = []
        if clean_failures:
            error_msg.append(
                f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: "
                + ', '.join(clean_failures[:5])
            )
        if evil_failures:
            error_msg.append(
                f"{len(evil_failures)} of {len(evil_files)} evil bypassed: "
                + ', '.join(evil_failures[:5])
            )
        if error_msg:
            pytest.fail(" | ".join(error_msg))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
