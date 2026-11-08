#!/bin/bash
set -e
mkdir -p /logs/verifier

BACKUP_DIR=$(mktemp -d)
cp -a /home/user/spatial_reads.csv "$BACKUP_DIR/spatial_reads.csv"
cp -a /home/user/mcmc_sampler.sh "$BACKUP_DIR/mcmc_sampler.sh"
cleanup() {
    cp -a "$BACKUP_DIR/spatial_reads.csv" /home/user/spatial_reads.csv
    cp -a "$BACKUP_DIR/mcmc_sampler.sh" /home/user/mcmc_sampler.sh
    rm -rf "$BACKUP_DIR"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import signal
import stat
import subprocess
import time
import uuid

PIPELINE = "/home/user/run_pipeline.sh"
READS = "/home/user/spatial_reads.csv"
SAMPLER = "/home/user/mcmc_sampler.sh"
OUTPUT = "/home/user/final_posterior.txt"


def run_pipeline(timeout=30):
    try:
        return subprocess.run(
            [PIPELINE],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f"Pipeline timed out after {timeout} seconds") from exc


def descendants(root_pid):
    parent_map = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/stat", "r") as f:
                fields = f.read().split()
            parent_map.setdefault(int(fields[3]), []).append(int(name))
        except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError, IndexError):
            pass

    found = set()
    pending = [root_pid]
    while pending:
        parent = pending.pop()
        for child in parent_map.get(parent, []):
            if child not in found:
                found.add(child)
                pending.append(child)
    return found


def test_run_pipeline_exists_and_executable():
    assert os.path.isfile(PIPELINE), f"Script {PIPELINE} does not exist."
    assert os.access(PIPELINE, os.X_OK), f"Script {PIPELINE} is not executable."


def test_run_pipeline_parallelization():
    assert os.path.isfile(PIPELINE), f"Script {PIPELINE} does not exist."
    with open(PIPELINE, "r") as f:
        content = f.read()
    assert "&" in content, "Script does not appear to use background processes (&)."
    assert "wait" in content, "Script does not appear to use the 'wait' command."


def test_pipeline_is_executed_and_original_output_is_correct():
    assert os.path.isfile(READS), f"Input file {READS} is missing."

    count = 0
    with open(READS, "r") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) >= 3 and "GATTACA" in parts[2]:
                count += 1

    expected_val = count * 1.374 + 15.2
    expected_stdout = subprocess.run(
        [SAMPLER, str(count)], check=True, stdout=subprocess.PIPE
    ).stdout

    try:
        os.unlink(OUTPUT)
    except FileNotFoundError:
        pass

    result = run_pipeline()
    assert result.returncode == 0, (
        f"Pipeline exited with status {result.returncode}. "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist."

    with open(OUTPUT, "rb") as f:
        output_bytes = f.read()
    assert output_bytes == expected_stdout, (
        "final_posterior.txt is not the exact standard output of mcmc_sampler.sh"
    )

    content = output_bytes.decode().strip()
    match = re.search(r"MCMC Posterior Mean:\s*([0-9.]+)", content)
    assert match is not None, (
        f"Could not parse MCMC Posterior Mean from {OUTPUT}. Content: {content}"
    )
    actual_val = float(match.group(1))
    assert abs(actual_val - expected_val) < 1e-4, (
        f"Expected posterior mean approx {expected_val}, but got {actual_val}"
    )


def test_randomized_pipeline_uses_sampler_and_parallel_workers():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    coordinates = [(50.0, 50.0), (75.0, 25.0), (25.0, 75.0), (75.0, 75.0)]
    expected = 0

    # A large, freshly generated input keeps real quadrant workers alive long
    # enough for their overlap to be observed and defeats fabricated fixed output.
    with open(READS, "w") as f:
        for i in range(500000):
            x, y = coordinates[i % 4]
            matched = rng.randrange(7) in (0, 1)
            if matched:
                expected += 1
                seq = "A" * 17 + "GATTACA" + "C" * 26
            else:
                seq = "C" * 50
            f.write(f"{x},{y},{seq}\n")

    nonce = uuid.uuid4().hex
    log_path = f"/tmp/sampler_call_{nonce}"
    marker_path = f"/tmp/sampler_entered_{nonce}"
    sampler_stdout = f"sampler-probe-{nonce}\n".encode()
    wrapper = f'''#!/bin/bash
printf '%s\\n%s\\n' "$#" "$1" > "{log_path}"
: > "{marker_path}"
printf '%s\\n' 'sampler-probe-{nonce}'
'''
    with open(SAMPLER, "w") as f:
        f.write(wrapper)
    os.chmod(SAMPLER, stat.S_IRWXU | stat.S_IRWXG | stat.S_IRWXO)

    try:
        os.unlink(OUTPUT)
    except FileNotFoundError:
        pass

    proc = subprocess.Popen(
        [PIPELINE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    max_parallel_descendants = 0
    deadline = time.monotonic() + 30
    try:
        while proc.poll() is None:
            if not os.path.exists(marker_path):
                max_parallel_descendants = max(
                    max_parallel_descendants, len(descendants(proc.pid))
                )
            if time.monotonic() > deadline:
                os.killpg(proc.pid, signal.SIGKILL)
                raise AssertionError("Pipeline timed out on randomized input")
            time.sleep(0.001)
        stdout, stderr = proc.communicate()
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()

    assert proc.returncode == 0, (
        f"Pipeline exited with status {proc.returncode}. "
        f"stderr: {stderr.decode(errors='replace')}"
    )
    assert max_parallel_descendants >= 4, (
        "Did not observe four concurrently running quadrant workers before the "
        f"sampler was called (maximum observed: {max_parallel_descendants})."
    )
    assert os.path.isfile(log_path), "The pipeline did not invoke mcmc_sampler.sh."
    with open(log_path, "r") as f:
        call = f.read().splitlines()
    assert call == ["1", str(expected)], (
        "mcmc_sampler.sh must be called once with the aggregated exact-match "
        f"count as its single argument; observed call data: {call!r}"
    )
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist."
    with open(OUTPUT, "rb") as f:
        actual_output = f.read()
    assert actual_output == sampler_stdout, (
        "final_posterior.txt is not the exact stdout of the sampler invoked by "
        "the pipeline"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
