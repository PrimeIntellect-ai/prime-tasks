#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import math
import os
import shutil
import subprocess
import tempfile
import pytest

WORKSPACE = "/home/user/workspace"
PACKAGE = os.path.join(WORKSPACE, "mcmc-bash-pkg-1.0")
DATASET = os.path.join(WORKSPACE, "dataset.csv")
GEN_SCRIPT = os.path.join(WORKSPACE, "generate_dataset.sh")


def test_package_exists_is_patched_and_is_correct():
    generator = os.path.join(PACKAGE, "mcmc_generator.sh")
    aggregator = os.path.join(PACKAGE, "aggregate.sh")
    assert os.path.isfile(generator), "Extracted mcmc_generator.sh not found."
    assert os.path.isfile(aggregator), "Extracted aggregate.sh not found."

    # The submitted package must not simply be the original, known-buggy package.
    with tempfile.TemporaryDirectory() as td:
        subprocess.run(
            ["tar", "-xzf", "/app/mcmc-bash-pkg-1.0.tar.gz", "-C", td],
            check=True,
        )
        original = os.path.join(td, "mcmc-bash-pkg-1.0")
        same_generator = filecmp.cmp(
            generator, os.path.join(original, "mcmc_generator.sh"), shallow=False
        )
        same_aggregator = filecmp.cmp(
            aggregator, os.path.join(original, "aggregate.sh"), shallow=False
        )
        assert not (same_generator and same_aggregator), (
            "The extracted package is byte-identical to the original buggy package."
        )

    # Exercise the actual patched generator repeatedly and derive the expected EMA.
    seed = 1234
    samples = 80
    awk_program = (
        'BEGIN { for(i=1; i<=n; i++) { srand(s+i); print rand() * 100 } }'
    )
    proc = subprocess.run(
        ["awk", "-v", f"s={seed}", "-v", f"n={samples}", awk_program],
        capture_output=True,
        text=True,
        check=True,
    )
    vals = [float(x) for x in proc.stdout.splitlines() if x.strip()]
    assert len(vals) == samples
    expected = vals[0]
    for val in vals[1:]:
        expected = 0.1 * val + 0.9 * expected

    outputs = []
    for _ in range(3):
        proc = subprocess.run(
            ["bash", "./mcmc_generator.sh", str(seed), str(samples)],
            cwd=PACKAGE,
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
        try:
            result = float(proc.stdout.strip())
        except ValueError:
            pytest.fail(f"Generator returned a non-numeric result: {proc.stdout!r}")
        assert math.isfinite(result), "Generator returned a non-finite EMA."
        outputs.append(result)

    assert len(set(outputs)) == 1, "Patched generator is not deterministic."
    assert abs(outputs[0] - expected) <= 1e-5, (
        f"Patched generator did not aggregate samples in numerical order: "
        f"got {outputs[0]}, expected {expected}"
    )


def test_dataset_exists():
    assert os.path.exists(DATASET), "dataset.csv not found in /home/user/workspace/"


def test_generate_dataset_script_orchestrates_exact_parallel_workload():
    assert os.path.isfile(GEN_SCRIPT), "generate_dataset.sh not found."
    assert os.path.getsize(GEN_SCRIPT) > 0, "generate_dataset.sh is empty."
    assert os.path.exists(DATASET), "The required executed dataset.csv is missing."

    generator = os.path.join(PACKAGE, "mcmc_generator.sh")
    state = "/tmp/verifier_gen_state"
    backup_generator = "/tmp/verifier_mcmc_generator.backup"
    backup_dataset = "/tmp/verifier_dataset.backup"
    shutil.rmtree(state, ignore_errors=True)
    os.makedirs(state)
    with open(os.path.join(state, "counts"), "w") as f:
        f.write("0 0\n")
    shutil.copy2(generator, backup_generator)
    shutil.copy2(DATASET, backup_dataset)

    # Replace only the generator entry point temporarily. This records the exact
    # seeds/sample counts requested and makes overlapping invocations observable.
    stub = r'''#!/bin/bash
set -e
STATE=/tmp/verifier_gen_state
seed=$1
samples=$2
exec 9>>"$STATE/lock"
flock 9
read -r active maximum < "$STATE/counts"
active=$((active + 1))
if [ "$active" -gt "$maximum" ]; then maximum=$active; fi
printf '%s %s\n' "$active" "$maximum" > "$STATE/counts"
printf '%s %s\n' "$seed" "$samples" >> "$STATE/calls"
flock -u 9
sleep 0.15
flock 9
read -r active maximum < "$STATE/counts"
active=$((active - 1))
printf '%s %s\n' "$active" "$maximum" > "$STATE/counts"
flock -u 9
printf '%s\n' "$seed"
'''

    try:
        with open(generator, "w") as f:
            f.write(stub)
        os.chmod(generator, 0o755)
        os.remove(DATASET)

        proc = subprocess.run(
            ["bash", GEN_SCRIPT],
            cwd=WORKSPACE,
            capture_output=True,
            text=True,
            timeout=90,
        )
        assert proc.returncode == 0, (
            f"generate_dataset.sh failed. stdout={proc.stdout!r} stderr={proc.stderr!r}"
        )

        calls_path = os.path.join(state, "calls")
        assert os.path.isfile(calls_path), (
            "generate_dataset.sh did not invoke the extracted MCMC generator."
        )
        with open(calls_path) as f:
            calls = [tuple(map(int, line.split())) for line in f if line.strip()]
        assert sorted(calls) == [(seed, 500) for seed in range(1000, 1100)], (
            "generate_dataset.sh must invoke the generator exactly once for every "
            "seed 1000..1099, with 500 samples each."
        )

        with open(os.path.join(state, "counts")) as f:
            active, maximum = map(int, f.read().split())
        assert active == 0
        assert maximum > 1, (
            "Generator invocations did not overlap; seeds must be generated in parallel."
        )

        assert os.path.isfile(DATASET), "generate_dataset.sh did not create dataset.csv."
        generated = []
        with open(DATASET) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split(",")
                assert len(parts) == 2, f"Invalid generated line: {line!r}"
                generated.append((int(parts[0]), float(parts[1])))
        assert generated == [(seed, float(seed)) for seed in range(1000, 1100)], (
            "generate_dataset.sh did not compile the generator outputs into a "
            "numerically sorted 100-line dataset.csv."
        )
    finally:
        shutil.copy2(backup_generator, generator)
        if os.path.exists(backup_dataset):
            shutil.copy2(backup_dataset, DATASET)


def test_dataset_format_and_accuracy():
    agent_file = DATASET
    assert os.path.exists(agent_file), "dataset.csv not found."

    # Compute reference data using awk to ensure identical PRNG sequence.
    reference_data = {}
    for seed in range(1000, 1100):
        awk_cmd = f"awk -v s={seed} 'BEGIN {{ for(i=1; i<=500; i++) {{ srand(s+i); printf \"%.6f\\n\", rand() * 100 }} }}'"
        proc = subprocess.run(awk_cmd, shell=True, capture_output=True, text=True)
        vals = [float(x) for x in proc.stdout.strip().split("\n")]

        ema = None
        for val in vals:
            if ema is None:
                ema = val
            else:
                ema = 0.1 * val + 0.9 * ema

        reference_data[seed] = ema

    max_err = 0.0
    agent_count = 0
    previous_seed = -1

    with open(agent_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            assert len(parts) == 2, f"Invalid format in line: '{line}'. Expected 'seed,val'"
            seed_str, val_str = parts
            try:
                seed = int(seed_str)
                val = float(val_str)
            except ValueError:
                pytest.fail(f"Could not parse numerical values from line: '{line}'")

            assert math.isfinite(val), f"EMA value must be finite in line: '{line}'"
            assert seed > previous_seed, f"Seeds are not sorted numerically. Found {seed} after {previous_seed}"
            previous_seed = seed

            if seed in reference_data:
                err = abs(reference_data[seed] - val)
                assert math.isfinite(err), f"Non-finite error for seed {seed}"
                max_err = max(max_err, err)
                agent_count += 1
            else:
                pytest.fail(f"Unexpected seed {seed} found in dataset.")

    assert agent_count == 100, f"Expected exactly 100 seeds, found {agent_count}."
    assert max_err <= 1e-4, f"Max Absolute Error exceeds tolerance. Max err: {max_err} > 1e-4"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
