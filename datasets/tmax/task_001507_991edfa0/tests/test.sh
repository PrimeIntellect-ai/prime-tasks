#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile
import uuid

import pytest

SANITIZER = "/home/user/sanitizer"
CLEAN = "/app/corpus/clean"
EVIL = "/app/corpus/evil"
LINE_RE = re.compile(r"^([^:\r\n]+): (ACCEPT|REJECT)$")


def test_results_files_exist():
    """Ensure the user saved the results to the specified files."""
    assert os.path.isfile("/home/user/clean_results.txt"), "/home/user/clean_results.txt is missing"
    assert os.path.isfile("/home/user/evil_results.txt"), "/home/user/evil_results.txt is missing"


def test_clean_corpus_accepted():
    """Ensure all instances in the clean corpus are accepted."""
    with open("/home/user/clean_results.txt", "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, "clean_results.txt is empty"

    rejected = []
    for line in lines:
        if not line.endswith("ACCEPT"):
            rejected.append(line)

    if rejected:
        pytest.fail(f"{len(rejected)} of {len(lines)} clean instances modified/rejected. Examples: {rejected[:5]}")


def test_evil_corpus_rejected():
    """Ensure all instances in the evil corpus are rejected."""
    with open("/home/user/evil_results.txt", "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, "evil_results.txt is empty"

    accepted = []
    for line in lines:
        if not line.endswith("REJECT"):
            accepted.append(line)

    if accepted:
        pytest.fail(f"{len(accepted)} of {len(lines)} evil instances bypassed/accepted. Examples: {accepted[:5]}")


def test_benchmark_script_exists():
    """Ensure the benchmark bash script was created."""
    assert os.path.isfile("/home/user/benchmark.sh"), "/home/user/benchmark.sh is missing"
    assert os.access("/home/user/benchmark.sh", os.X_OK), "/home/user/benchmark.sh is not executable"


def read_joined(directory):
    specifications = [
        ("signals.csv", "alpha_signal"),
        ("fluxes.csv", "beta_flux"),
        ("resonances.csv", "gamma_resonance"),
    ]
    joined = {}
    id_sets = []
    for filename, feature in specifications:
        path = os.path.join(directory, filename)
        assert os.path.isfile(path), f"missing corpus file: {path}"
        rows = {}
        with open(path, newline="") as f:
            reader = csv.DictReader(f)
            assert reader.fieldnames == ["instance_id", feature]
            for row in reader:
                instance_id = row["instance_id"]
                assert instance_id not in rows, f"duplicate ID {instance_id} in {path}"
                float(row[feature])
                rows[instance_id] = row[feature]
        assert len(rows) == 1000, f"expected 1000 rows in {path}, found {len(rows)}"
        id_sets.append(set(rows))
        for instance_id, value in rows.items():
            joined.setdefault(instance_id, {})[feature] = value

    assert id_sets[0] == id_sets[1] == id_sets[2], "CSV instance IDs do not join one-to-one"
    assert len(joined) == 1000
    return joined


def parse_output(text, source):
    lines = text.splitlines()
    assert lines, f"{source} is empty"
    assert all(line.strip() for line in lines), f"{source} contains blank output lines"
    parsed = {}
    for line in lines:
        match = LINE_RE.fullmatch(line.strip())
        assert match, f"invalid output line in {source}: {line!r}"
        instance_id, decision = match.groups()
        assert instance_id not in parsed, f"duplicate instance_id {instance_id!r} in {source}"
        parsed[instance_id] = decision
    return parsed


def parse_file(path):
    with open(path) as f:
        return parse_output(f.read(), path)


def run_sanitizer(directory, timeout=30):
    completed = subprocess.run(
        [SANITIZER, directory],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )
    assert completed.returncode == 0, (
        f"sanitizer failed for {directory} with exit code {completed.returncode}: "
        f"{completed.stderr[:1000]}"
    )
    return parse_output(completed.stdout, f"sanitizer stdout for {directory}")


def assert_exact_decisions(results, expected_ids, expected_decision, source):
    assert len(results) == 1000, f"{source} must contain exactly 1000 results"
    assert set(results) == set(expected_ids), f"{source} IDs do not exactly match the joined CSV IDs"
    wrong = [instance_id for instance_id, decision in results.items() if decision != expected_decision]
    assert not wrong, f"{source} has {len(wrong)} wrong decisions; examples: {wrong[:5]}"


def test_sanitizer_is_executable_compiled_artifact():
    assert os.path.isfile(SANITIZER), f"{SANITIZER} is missing"
    assert os.access(SANITIZER, os.X_OK), f"{SANITIZER} is not executable"
    with open(SANITIZER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sanitizer must be a compiled executable"


def test_saved_results_match_csvs_and_real_execution():
    clean_rows = read_joined(CLEAN)
    evil_rows = read_joined(EVIL)

    saved_clean = parse_file("/home/user/clean_results.txt")
    saved_evil = parse_file("/home/user/evil_results.txt")
    assert_exact_decisions(saved_clean, clean_rows, "ACCEPT", "clean_results.txt")
    assert_exact_decisions(saved_evil, evil_rows, "REJECT", "evil_results.txt")

    live_clean = run_sanitizer(CLEAN)
    live_evil = run_sanitizer(EVIL)
    assert_exact_decisions(live_clean, clean_rows, "ACCEPT", "live clean output")
    assert_exact_decisions(live_evil, evil_rows, "REJECT", "live evil output")
    assert live_clean == saved_clean, "clean_results.txt does not match a fresh sanitizer run"
    assert live_evil == saved_evil, "evil_results.txt does not match a fresh sanitizer run"


def test_sanitizer_joins_shuffled_mixed_csvs_and_classifies_each_instance():
    clean_rows = read_joined(CLEAN)
    evil_rows = read_joined(EVIL)
    rng = random.Random(secrets.randbits(128))
    clean_ids = rng.sample(list(clean_rows), 128)
    evil_ids = rng.sample(list(evil_rows), 128)

    records = []
    expected = {}
    base = rng.randrange(1000000, 9000000)
    for index, (label, old_id) in enumerate(
        [("ACCEPT", value) for value in clean_ids] + [("REJECT", value) for value in evil_ids]
    ):
        new_id = str(base + index * 7)
        source = clean_rows if label == "ACCEPT" else evil_rows
        records.append((new_id, source[old_id]))
        expected[new_id] = label

    with tempfile.TemporaryDirectory(prefix="sanitizer-joined-") as directory:
        for filename, feature in [
            ("signals.csv", "alpha_signal"),
            ("fluxes.csv", "beta_flux"),
            ("resonances.csv", "gamma_resonance"),
        ]:
            independently_shuffled = records[:]
            rng.shuffle(independently_shuffled)
            with open(os.path.join(directory, filename), "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(["instance_id", feature])
                for instance_id, values in independently_shuffled:
                    writer.writerow([instance_id, values[feature]])

        actual = run_sanitizer(directory)
        assert set(actual) == set(expected), "sanitizer did not emit exactly one result for every joined mixed ID"
        wrong = [key for key in expected if actual[key] != expected[key]]
        assert not wrong, f"sanitizer misclassified {len(wrong)} mixed instances; examples: {wrong[:5]}"


def test_benchmark_actually_invokes_sanitizer_on_given_directory():
    token = uuid.uuid4().hex
    backup = f"/home/user/.sanitizer.verifier.{token}"
    marker = f"/tmp/benchmark-marker-{token}"
    alias_root = tempfile.mkdtemp(prefix="benchmark-input-")
    alias = os.path.join(alias_root, "corpus")
    os.symlink(CLEAN, alias)

    os.replace(SANITIZER, backup)
    try:
        wrapper = (
            "#!/bin/bash\n"
            f"printf '%s\\0' \"$@\" >> '{marker}'\n"
            f"exec '{backup}' \"$@\"\n"
        )
        with open(SANITIZER, "w") as f:
            f.write(wrapper)
        os.chmod(SANITIZER, 0o755)

        completed = subprocess.run(
            ["/home/user/benchmark.sh", alias],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
            check=False,
        )
        assert completed.returncode == 0, (
            f"benchmark.sh failed with exit code {completed.returncode}: "
            f"{completed.stderr.decode(errors='replace')[:1000]}"
        )
        assert os.path.isfile(marker), "benchmark.sh did not invoke /home/user/sanitizer"
        with open(marker, "rb") as f:
            arguments = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
        assert alias in arguments, "benchmark.sh did not pass its supplied directory to the sanitizer"
    finally:
        if os.path.lexists(SANITIZER):
            os.unlink(SANITIZER)
        if os.path.exists(backup):
            os.replace(backup, SANITIZER)
        if os.path.exists(marker):
            os.unlink(marker)
        shutil.rmtree(alias_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
