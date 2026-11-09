#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json

def test_clean_state_json_exists():
    """Verify that the final clean_state.json file exists."""
    filepath = "/home/user/clean_state.json"
    assert os.path.exists(filepath), f"The file {filepath} does not exist. Ensure your script generates it."
    assert os.path.isfile(filepath), f"{filepath} is not a regular file."

def test_clean_state_json_contents():
    """Verify the contents of the generated clean_state.json."""
    filepath = "/home/user/clean_state.json"
    assert os.path.exists(filepath), "clean_state.json is missing."

    try:
        with open(filepath, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        assert False, f"Failed to parse {filepath} as JSON: {e}"

    assert isinstance(data, dict), f"Expected JSON root to be an object (dict), got {type(data).__name__}."

    expected_alpha = "setting1=A_updated\nsetting2=B_updated\nsetting3=C"
    expected_beta = "beta_mode=false\nnodes=8\ncache=redis"

    assert "alpha" in data, "Host 'alpha' is missing from the JSON output."
    assert "beta" in data, "Host 'beta' is missing from the JSON output."

    actual_alpha = data["alpha"].strip()
    actual_beta = data["beta"].strip()

    assert actual_alpha == expected_alpha, (
        f"Incorrect configuration for host 'alpha'.\n"
        f"Expected:\n{expected_alpha}\n\nGot:\n{actual_alpha}"
    )

    assert actual_beta == expected_beta, (
        f"Incorrect configuration for host 'beta'.\n"
        f"Expected:\n{expected_beta}\n\nGot:\n{actual_beta}"
    )

    # Ensure no extra unexpected hosts are present
    expected_keys = {"alpha", "beta"}
    actual_keys = set(data.keys())
    extra_keys = actual_keys - expected_keys
    assert not extra_keys, f"Found unexpected hosts in the JSON output: {extra_keys}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
