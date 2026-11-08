#!/bin/bash
set -e
mkdir -p /logs/verifier

ORIGINAL_ORACLE="$(mktemp /tmp/mc_oracle.original.XXXXXX)"
INVOCATION_LOG="$(mktemp /tmp/mc_oracle.invocations.XXXXXX)"
cp -p /app/mc_oracle "$ORIGINAL_ORACLE"

restore_oracle() {
    cp -p "$ORIGINAL_ORACLE" /app/mc_oracle
    rm -f "$ORIGINAL_ORACLE" "$INVOCATION_LOG"
}
trap restore_oracle EXIT

cat > /app/mc_oracle <<EOF
#!/bin/bash
printf '%s\t%s\t%s\t%s\t%s\n' "\$#" "\${1-}" "\${OMP_NUM_THREADS-}" "\${OMPI_COMM_WORLD_SIZE-}" "\${OMPI_COMM_WORLD_RANK-}" >> "$INVOCATION_LOG"
exec "$ORIGINAL_ORACLE" "\$@"
EOF
chmod 755 /app/mc_oracle
export VALIDATOR_INVOCATION_LOG="$INVOCATION_LOG"
export OMPI_ALLOW_RUN_AS_ROOT=1
export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
export OMPI_MCA_rmaps_base_oversubscribe=1

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import time

import pytest

SCRIPT_PATH = "/home/user/validate_config.sh"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"
LOG_PATH = os.environ["VALIDATOR_INVOCATION_LOG"]


def parse_config(path):
    values = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            key, value = line.strip().split("=", 1)
            values[key] = int(value)
    return values


def run_and_verify(path, expected_returncode, expect_timeout=False):
    values = parse_config(path)
    open(LOG_PATH, "w").close()

    started = time.monotonic()
    result = subprocess.run(
        [SCRIPT_PATH, path],
        capture_output=True,
        text=True,
        timeout=7,
        env=os.environ.copy(),
    )
    elapsed = time.monotonic() - started

    assert result.returncode == expected_returncode, (
        f"{path} returned {result.returncode}, expected {expected_returncode}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    if expect_timeout:
        assert elapsed >= 1.5, f"Deadlocking configuration was rejected too quickly ({elapsed:.2f}s); timeout was not exercised"
        assert elapsed <= 5.5, f"Deadlocking configuration was not stopped promptly ({elapsed:.2f}s)"

    with open(LOG_PATH, encoding="utf-8") as handle:
        records = [line.rstrip("\n").split("\t") for line in handle if line.strip()]

    ranks = values["RANKS"]
    threads = values["THREADS"]
    assert len(records) == ranks, f"Expected one /app/mc_oracle invocation per MPI rank ({ranks}), got {records!r}"
    assert all(len(record) == 5 for record in records), f"Malformed invocation records: {records!r}"
    assert all(record[0] == "1" for record in records), "Oracle was not invoked with exactly one argument"
    assert all(record[1] == path for record in records), "Oracle was not given the supplied configuration path"
    assert all(record[2] == str(threads) for record in records), "OMP_NUM_THREADS did not match THREADS"
    assert all(record[3] == str(ranks) for record in records), "MPI world size did not match RANKS"
    assert sorted(int(record[4]) for record in records) == list(range(ranks)), "Oracle was not launched once in every MPI rank"


def write_random_config(directory, samples, ranks, threads):
    path = os.path.join(directory, secrets.token_hex(12) + ".cfg")
    lines = [f"SAMPLES={samples}\n", f"RANKS={ranks}\n", f"THREADS={threads}\n"]
    random.SystemRandom().shuffle(lines)
    with open(path, "w", encoding="utf-8") as handle:
        handle.writelines(lines)
    return path


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_accepts_exactly_one_argument():
    no_arg = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=4)
    two_args = subprocess.run([SCRIPT_PATH, "a", "b"], capture_output=True, text=True, timeout=4)
    assert no_arg.returncode != 0
    assert two_args.returncode != 0


def test_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]
    assert clean_files, "No files found in clean corpus directory"
    for filename in clean_files:
        run_and_verify(os.path.join(CLEAN_CORPUS, filename), 0)


def test_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f))]
    assert evil_files, "No files found in evil corpus directory"
    for filename in evil_files:
        path = os.path.join(EVIL_CORPUS, filename)
        run_and_verify(path, 1, expect_timeout=parse_config(path)["RANKS"] > 4)


def test_independently_generated_configurations():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="cfg-" + secrets.token_hex(8) + "-") as directory:
        generated = []

        for _ in range(2):
            ranks = rng.randint(1, 4)
            threads = rng.randint(1, 4)
            samples = ranks * threads * rng.randint(17, 2000)
            generated.append((write_random_config(directory, samples, ranks, threads), 0, False))

        for _ in range(2):
            ranks, threads = rng.choice([(2, 2), (2, 3), (3, 2), (4, 1), (4, 3)])
            samples = ranks * threads * rng.randint(17, 2000) + 1
            generated.append((write_random_config(directory, samples, ranks, threads), 1, False))

        generated.append((write_random_config(directory, 1000 + rng.randint(1, 100), rng.randint(1, 4), 0), 1, False))

        threads = rng.randint(1, 3)
        samples = 5 * threads * rng.randint(17, 100)
        generated.append((write_random_config(directory, samples, 5, threads), 1, True))

        rng.shuffle(generated)
        for path, expected, expect_timeout in generated:
            run_and_verify(path, expected, expect_timeout=expect_timeout)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    RESULT=1
else
    RESULT=0
fi

restore_oracle
trap - EXIT
echo "$RESULT" > /logs/verifier/reward.txt
