#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_optimization_report_exists():
    """Test that the output report file exists."""
    output_file = "/home/user/optimization_report.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

def test_optimization_report_content():
    """Test that the output report file contains the correct schema and shortest path."""
    output_file = "/home/user/optimization_report.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    expected_content = """SCHEMA:
App -> Auth
App -> Cache
App -> DB
Auth -> DB
Cache -> DB
Gateway -> App

SHORTEST_PATH_LATENCY: 45
SHORTEST_PATH: Gateway_Alpha -> App_1 -> Cache_1 -> DB_Omega"""

    with open(output_file, "r") as f:
        content = f.read().strip()

    assert content == expected_content, (
        f"Content of {output_file} does not match expected output.\n"
        f"Expected:\n{expected_content}\n\nGot:\n{content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
