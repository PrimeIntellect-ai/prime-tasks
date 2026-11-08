#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import time
import subprocess
import json
import shutil
import pytest
from urllib.parse import urlparse, parse_qs

ROUTES_FILE = "/app/routes.json"
EXPECTED_RELEASE = "/home/user/release_14.5.2-beta.json"
SCRIPT_PATH = "/home/user/merge_builds.py"


def compute_expected():
    """Independently reproduce the original script's logical output in O(N)."""
    with open(ROUTES_FILE, "r") as f:
        routes = json.load(f)

    parsed = []
    maximum_by_module = {}
    for route in routes:
        module = parse_qs(urlparse(route["url"]).query).get("module", [""])[0]
        build_id = route["build_id"]
        parsed.append((module, build_id))
        if module not in maximum_by_module or build_id > maximum_by_module[module]:
            maximum_by_module[module] = build_id

    # The legacy implementation emits the first occurrence of a maximum build
    # for each module, in the order those maximum occurrences appear.
    expected = []
    emitted = set()
    for module, build_id in parsed:
        if module not in emitted and build_id == maximum_by_module[module]:
            expected.append({"module": module, "build_id": build_id})
            emitted.add(module)
    return expected


def load_json(path):
    with open(path, "r") as f:
        return json.load(f)


def test_output_file_exists_and_valid():
    """Check that the correctly named release exists and has exact contents."""
    assert os.path.exists(EXPECTED_RELEASE), (
        f"Output file {EXPECTED_RELEASE} missing. Did you extract the correct "
        "version from the image and run the script?"
    )

    with open(EXPECTED_RELEASE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {EXPECTED_RELEASE} is not valid JSON.")

    assert data == compute_expected(), "Final release manifest does not contain the latest build for each module."


def test_performance_metric():
    """Execute the refactored script, validate its output, and measure runtime."""
    test_out = "/home/user/test_out.json"
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is not a regular file."

    # Ensure a no-op script cannot pass by relying on an output left in advance.
    if os.path.lexists(test_out):
        if os.path.isdir(test_out) and not os.path.islink(test_out):
            shutil.rmtree(test_out)
        else:
            os.unlink(test_out)

    start = time.time()
    result = subprocess.run(
        ["python3", SCRIPT_PATH, test_out],
        capture_output=True,
        text=True,
    )
    duration = time.time() - start

    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"
    assert duration <= 1.0, (
        f"Script took {duration:.2f}s, which is slower than threshold 1.0s. "
        "Ensure the O(N^2) complexity was reduced."
    )
    assert os.path.isfile(test_out), "Script exited successfully but did not create its requested output file."

    try:
        generated = load_json(test_out)
    except json.JSONDecodeError:
        pytest.fail(f"Script output {test_out} is not valid JSON.")

    assert generated == compute_expected(), "Refactored script produced an incorrect merged manifest."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
