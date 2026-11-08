#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import difflib


def test_final_documentation_similarity():
    target_path = "/home/user/final_documentation.md"
    golden = "Welcome to NovaTech.\n\nNovaTech is great!"

    assert os.path.exists(target_path), f"Output file missing: {target_path}"

    with open(target_path, "r", encoding="utf-8") as f:
        target = f.read().strip()

    ratio = difflib.SequenceMatcher(None, target, golden).ratio()
    assert ratio >= 0.98, (
        f"Similarity ratio {ratio:.4f} is below threshold 0.98.\n\n"
        f"Target content:\n{target}\n\nExpected content:\n{golden}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
