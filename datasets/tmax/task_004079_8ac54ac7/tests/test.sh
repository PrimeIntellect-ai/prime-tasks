#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import secrets
import subprocess
import tempfile


def expected_summary(path):
    total = 0
    logins = 0
    with open(path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            parts = line.rstrip("\n").split("\t")
            assert len(parts) == 3, f"Input line does not have 3 columns: {line!r}"
            total += 1
            if parts[2] == "login":
                logins += 1
    return f"MINIMAL_STAT: {total} total, {logins} logins"


def run_processor(binary, input_path):
    result = subprocess.run(
        [binary, input_path], capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, (
        f"{binary} failed on {input_path}: stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    return result.stdout.strip()


def test_processor_patched():
    """Test that processor.c has been successfully patched."""
    src_file = "/home/user/src/processor.c"
    patch_file = "/home/user/src/update.patch"
    assert os.path.isfile(src_file), f"Source file {src_file} does not exist."
    with open(src_file, "r") as f:
        content = f.read()
    assert "char uid[256];" in content, "Source file does not appear to be patched with the new schema variables."
    assert "MINIMAL_CONTAINER" in content, "Source file does not appear to be patched with MINIMAL_CONTAINER logic."

    # Confirm that the supplied update patch can be cleanly reversed from the
    # submitted source, rather than trusting the presence of two keywords.
    result = subprocess.run(
        ["patch", "--dry-run", "--reverse", "--batch", "--silent", src_file, patch_file],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        "processor.c is not the result of applying update.patch cleanly: "
        f"{result.stdout}{result.stderr}"
    )


def test_binary_compiled_statically():
    """Test that the binary is compiled and statically linked."""
    bin_file = "/home/user/bin/processor"
    assert os.path.isfile(bin_file), f"Binary {bin_file} does not exist."
    assert os.access(bin_file, os.X_OK), f"Binary {bin_file} is not executable."

    result = subprocess.run(["file", bin_file], capture_output=True, text=True)
    assert "statically linked" in result.stdout.lower(), f"Binary {bin_file} is not statically linked. 'file' output: {result.stdout}"


def test_data_migrated_correctly():
    """Test that the data was migrated correctly to the new schema."""
    old_file = "/home/user/data/old_events.tsv"
    new_file = "/home/user/data/new_events.tsv"

    assert os.path.isfile(old_file), f"Original data file {old_file} is missing."
    assert os.path.isfile(new_file), f"Migrated data file {new_file} does not exist."

    with open(old_file, "r") as f:
        old_lines = f.read().strip().split("\n")

    with open(new_file, "r") as f:
        new_lines = f.read().strip().split("\n")

    assert len(old_lines) == len(new_lines), "Migrated data file does not have the same number of lines as the original."

    for old_line, new_line in zip(old_lines, new_lines):
        if not old_line.strip():
            continue

        old_parts = old_line.split("\t")
        new_parts = new_line.split("\t")

        assert len(new_parts) == 3, f"Migrated line does not have 3 columns: {new_line}"

        expected_uid = f"U-{old_parts[0]}"
        assert new_parts[0] == expected_uid, f"Expected uid {expected_uid}, got {new_parts[0]}"

        expected_time = datetime.datetime.fromtimestamp(int(old_parts[1]), tz=datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        assert new_parts[1] == expected_time, f"Expected time {expected_time}, got {new_parts[1]}"

        assert new_parts[2] == old_parts[2], f"Expected action {old_parts[2]}, got {new_parts[2]}"


def test_summary_output():
    """Test that the summary output is correct, indicating proper macro usage and processing."""
    out_file = "/home/user/output/summary.txt"
    assert os.path.isfile(out_file), f"Output file {out_file} does not exist."

    with open(out_file, "r") as f:
        content = f.read().strip()

    old_file = "/home/user/data/old_events.tsv"
    total = 0
    logins = 0
    if os.path.isfile(old_file):
        with open(old_file, "r") as f:
            for line in f:
                if not line.strip():
                    continue
                total += 1
                if line.strip().endswith("\tlogin"):
                    logins += 1

    expected_output = f"MINIMAL_STAT: {total} total, {logins} logins"
    assert content == expected_output, f"Output file content '{content}' does not match expected '{expected_output}'. This checks both processing logic and the -DMINIMAL_CONTAINER compilation flag."


def test_submitted_binary_executes_patched_minimal_logic():
    """Execute both the submitted binary and a macro-enabled build of the patched source."""
    submitted = "/home/user/bin/processor"
    source = "/home/user/src/processor.c"
    migrated = "/home/user/data/new_events.tsv"
    summary = "/home/user/output/summary.txt"

    with tempfile.TemporaryDirectory() as td:
        reference = os.path.join(td, "reference_processor")
        build = subprocess.run(
            ["gcc", "-static", "-DMINIMAL_CONTAINER", source, "-o", reference],
            capture_output=True,
            text=True,
        )
        assert build.returncode == 0, (
            "Patched processor.c cannot be compiled statically with "
            f"-DMINIMAL_CONTAINER: {build.stdout}{build.stderr}"
        )

        expected = expected_summary(migrated)
        submitted_output = run_processor(submitted, migrated)
        reference_output = run_processor(reference, migrated)
        assert submitted_output == expected
        assert reference_output == expected
        with open(summary, "r") as f:
            assert f.read().strip() == submitted_output, (
                "summary.txt is not the output produced by the submitted processor "
                "for new_events.tsv"
            )

        rng = secrets.SystemRandom()
        cases = [[], ["logout", "view", "purchase"]]
        for _ in range(3):
            actions = ["login"] * rng.randint(1, 7)
            actions += [rng.choice(["logout", "view", "purchase", "login_extra"])
                        for _ in range(rng.randint(1, 8))]
            rng.shuffle(actions)
            cases.append(actions)

        for case_number, actions in enumerate(cases):
            fixture = os.path.join(td, f"events_{case_number}.tsv")
            with open(fixture, "w") as f:
                for i, action in enumerate(actions):
                    f.write(f"U-{9000 + i}\t2031-04-05T06:07:{i % 60:02d}Z\t{action}\n")

            expected = expected_summary(fixture)
            assert run_processor(submitted, fixture) == expected, (
                "Submitted processor does not implement the patched counting logic "
                "with the MINIMAL_CONTAINER formatter"
            )
            assert run_processor(reference, fixture) == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
