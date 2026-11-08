#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import stat
import subprocess

SCRIPT_PATH = "/home/user/dep_resolver.py"
DEPS_PATH = "/home/user/deps.json"
CHECKSUM_PATH = "/home/user/checksum.txt"

BASELINE = {
    "app": {"data": "app_data_v1", "deps": ["libA", "libB"]},
    "libA": {"data": "libA_data_v2", "deps": ["libC"]},
    "libB": {"data": "libB_data_v1", "deps": ["libC", "libD"]},
    "libC": {"data": "libC_data_v3", "deps": ["libE"]},
    "libD": {"data": "libD_data_v1", "deps": ["libE"]},
    "libE": {"data": "libE_data_v2", "deps": []},
}


def expected_checksum(graph, node="app", memo=None):
    if memo is None:
        memo = {}
    if node in memo:
        return memo[node]

    digest = hashlib.md5()
    digest.update(graph[node]["data"].encode("utf-8"))
    for dependency in sorted(graph[node]["deps"]):
        digest.update(expected_checksum(graph, dependency, memo).encode("utf-8"))
    memo[node] = digest.hexdigest()
    return memo[node]


def run_resolver(graph):
    with open(DEPS_PATH, "w", encoding="utf-8") as handle:
        json.dump(graph, handle)

    if os.path.exists(CHECKSUM_PATH):
        os.remove(CHECKSUM_PATH)

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"dep_resolver.py failed under Python 3. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )

    assert os.path.isfile(CHECKSUM_PATH), (
        f"File {CHECKSUM_PATH} is missing. Did the script run successfully?"
    )
    with open(CHECKSUM_PATH, "r", encoding="utf-8") as handle:
        return handle.read().strip()


def test_checksum_file():
    assert os.path.exists(SCRIPT_PATH), f"File {SCRIPT_PATH} is missing."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file."

    original_deps = None
    original_checksum = None
    deps_existed = os.path.exists(DEPS_PATH)
    checksum_existed = os.path.exists(CHECKSUM_PATH)
    if deps_existed:
        with open(DEPS_PATH, "rb") as handle:
            original_deps = handle.read()
    if checksum_existed:
        with open(CHECKSUM_PATH, "rb") as handle:
            original_checksum = handle.read()

    try:
        content = run_resolver(BASELINE)
        expected_checksum_value = "c783281b373ef801dff0340b106c5bc2"
        assert content == expected_checksum_value, (
            f"Checksum in {CHECKSUM_PATH} is incorrect. "
            f"Expected {expected_checksum_value}, got {content}."
        )

        nonce = secrets.token_hex(24)
        varied_graph = {
            name: {
                "data": f"{entry['data']}::{nonce}::{name}",
                "deps": list(reversed(entry["deps"])),
            }
            for name, entry in BASELINE.items()
        }
        varied_expected = expected_checksum(varied_graph)
        varied_actual = run_resolver(varied_graph)
        assert varied_actual == varied_expected, (
            "dep_resolver.py did not compute the checksum from the supplied graph: "
            f"expected {varied_expected}, got {varied_actual}."
        )
    finally:
        if deps_existed:
            with open(DEPS_PATH, "wb") as handle:
                handle.write(original_deps)
        elif os.path.exists(DEPS_PATH):
            os.remove(DEPS_PATH)

        if checksum_existed:
            with open(CHECKSUM_PATH, "wb") as handle:
                handle.write(original_checksum)
        elif os.path.exists(CHECKSUM_PATH):
            os.remove(CHECKSUM_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
