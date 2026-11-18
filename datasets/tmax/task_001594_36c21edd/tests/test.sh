#!/bin/bash
mkdir -p /logs/verifier

REAL_ENGINE="/app/sim_engine.__verifier_real"
restore_engine() {
    if [ -e "$REAL_ENGINE" ]; then
        rm -f /app/sim_engine
        mv "$REAL_ENGINE" /app/sim_engine
    fi
}
trap restore_engine EXIT

rm -f "$REAL_ENGINE"
if ! mv /app/sim_engine "$REAL_ENGINE"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'WRAPPER_EOF' > /app/sim_engine
#!/usr/bin/env python3
import fcntl
import json
import os
import sys

REAL_ENGINE = "/app/sim_engine.__verifier_real"
MANIFEST = "/tmp/filter_sims_manifest.json"
STATE = "/tmp/filter_sims_engine_state.json"
CALL_LOG = "/tmp/filter_sims_engine_calls.jsonl"

if len(sys.argv) != 2:
    os.execv(REAL_ENGINE, [REAL_ENGINE] + sys.argv[1:])

path = os.path.abspath(sys.argv[1])
with open(CALL_LOG, "a", encoding="utf-8") as log:
    fcntl.flock(log.fileno(), fcntl.LOCK_EX)
    log.write(json.dumps(path) + "\n")
    log.flush()
    fcntl.flock(log.fileno(), fcntl.LOCK_UN)

try:
    with open(MANIFEST, "r", encoding="utf-8") as f:
        manifest = json.load(f)
except (OSError, ValueError):
    manifest = {}

if path not in manifest:
    os.execv(REAL_ENGINE, [REAL_ENGINE, sys.argv[1]])

with open(STATE, "a+", encoding="utf-8") as state_file:
    fcntl.flock(state_file.fileno(), fcntl.LOCK_EX)
    state_file.seek(0)
    try:
        state = json.load(state_file)
    except (ValueError, OSError):
        state = {}
    count = int(state.get(path, 0))
    state[path] = count + 1
    state_file.seek(0)
    state_file.truncate()
    json.dump(state, state_file)
    state_file.flush()
    fcntl.flock(state_file.fileno(), fcntl.LOCK_UN)

if manifest[path]:
    energy = 42.0
else:
    energy = 22.0 if count % 2 == 0 else 62.0
print(f"final_energy: {energy:.6f}")
WRAPPER_EOF
chmod 755 /app/sim_engine
rm -f /tmp/filter_sims_engine_state.json /tmp/filter_sims_engine_calls.jsonl /tmp/filter_sims_manifest.json

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import secrets
import shutil
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/filter_sims"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CALL_LOG = "/tmp/filter_sims_engine_calls.jsonl"
MANIFEST = "/tmp/filter_sims_manifest.json"
MIN_TRIALS = 5

HIDDEN_DIR = tempfile.mkdtemp(prefix="sim_inputs_")
_hidden_paths = []
for _ in range(16):
    name = "case_" + secrets.token_hex(8) + ".params"
    path = os.path.abspath(os.path.join(HIDDEN_DIR, name))
    with open(path, "w", encoding="utf-8") as f:
        f.write(str(secrets.randbelow(1_000_000) + 1000) + "\n")
    _hidden_paths.append(path)

_flags = ([True] * 8) + ([False] * 8)
secrets.SystemRandom().shuffle(_flags)
HIDDEN_BEHAVIOR = dict(zip(_hidden_paths, _flags))
with open(MANIFEST, "w", encoding="utf-8") as f:
    json.dump(HIDDEN_BEHAVIOR, f)


def calls_so_far():
    counts = collections.Counter()
    try:
        with open(CALL_LOG, "r", encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    counts[json.loads(line)] += 1
    except FileNotFoundError:
        pass
    return counts


def run_and_validate(directory, expected_paths):
    before = calls_so_far()
    result = subprocess.run([SCRIPT_PATH, directory], capture_output=True, text=True, timeout=180)
    assert result.returncode == 0, (
        f"Script failed on {directory} with return code {result.returncode}. "
        f"Stderr: {result.stderr}"
    )

    lines = result.stdout.splitlines()
    assert all(line and line == line.strip() for line in lines), (
        "Output must contain only one absolute path per non-empty line"
    )
    assert all(os.path.isabs(line) for line in lines), "Every preserved path must be absolute"
    assert len(lines) == len(set(lines)), "A preserved file was printed more than once"
    assert set(lines) == set(expected_paths), (
        f"Incorrect preserved paths. Missing: {sorted(set(expected_paths) - set(lines))}; "
        f"unexpected: {sorted(set(lines) - set(expected_paths))}"
    )

    after = calls_so_far()
    input_files = [
        os.path.abspath(os.path.join(directory, name))
        for name in os.listdir(directory)
        if os.path.isfile(os.path.join(directory, name))
    ]
    insufficient = {
        path: after[path] - before[path]
        for path in input_files
        if after[path] - before[path] < MIN_TRIALS
    }
    assert not insufficient, (
        "Each parameter file must be evaluated by /app/sim_engine multiple times; "
        f"insufficient calls: {insufficient}"
    )


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_clean_corpus_preserved():
    expected_files = {
        os.path.abspath(os.path.join(CLEAN_CORPUS_DIR, f))
        for f in os.listdir(CLEAN_CORPUS_DIR)
        if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))
    }
    run_and_validate(CLEAN_CORPUS_DIR, expected_files)


def test_evil_corpus_rejected():
    run_and_validate(EVIL_CORPUS_DIR, set())


def test_randomized_mixed_corpus_uses_observed_stability():
    expected = {path for path, stable in HIDDEN_BEHAVIOR.items() if stable}
    run_and_validate(HIDDEN_DIR, expected)


def teardown_module(module):
    shutil.rmtree(HIDDEN_DIR, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
else
    reward=0
fi

restore_engine
trap - EXIT
echo "$reward" > /logs/verifier/reward.txt
