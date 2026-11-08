#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import tempfile
import pytest

APP = "/home/user/app"
SOURCE = os.path.join(APP, "processor.c")
FIXED = os.path.join(APP, "processor_fixed")
TRIGGER = 8492


def run_processor(executable, values, timeout=3.0):
    data = (" ".join(str(v) for v in values) + "\n").encode()
    try:
        result = subprocess.run(
            [executable], input=data, capture_output=True,
            timeout=timeout, check=False
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{executable} timed out for input {values!r}")
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode} for {values!r}; "
        f"stderr={result.stderr.decode(errors='replace')!r}"
    )
    output = result.stdout.decode("utf-8", errors="replace").strip()
    expected = f"Result: {sum(values)}"
    assert output == expected, (
        f"Incorrect output from {executable} for {values!r}: "
        f"expected {expected!r}, got {output!r}"
    )


def test_trigger_txt():
    trigger_file = os.path.join(APP, "trigger.txt")
    assert os.path.isfile(trigger_file), f"The file {trigger_file} does not exist."
    with open(trigger_file, "r") as f:
        content = f.read().strip()
    assert content == "8492", (
        "The trigger file does not contain the correct triggering integer. "
        f"Found: {content}"
    )


def test_fuzzing_script_exists():
    excluded = {"processor", "processor_fixed", "processor.c", "trigger.txt"}
    candidates = []
    for root, dirs, files in os.walk(APP):
        for name in files:
            path = os.path.join(root, name)
            if name in excluded or not os.path.isfile(path):
                continue
            try:
                if os.path.getsize(path) > 1024 * 1024:
                    continue
                with open(path, "rb") as f:
                    raw = f.read()
                text = raw.decode("utf-8")
            except (OSError, UnicodeDecodeError):
                continue

            is_script = (
                name.endswith((".py", ".sh", ".bash"))
                or text.startswith("#!")
                or bool(os.stat(path).st_mode & stat.S_IXUSR)
            )
            compact = re.sub(r"[\s_]", "", text.lower())
            refers_to_target = "processor" in text.lower()
            covers_range = (
                "range(1,10001" in compact
                or "{1..10000}" in compact
                or re.search(r"\bseq\s+(?:-?\w+\s+)*1\s+10000\b", text.lower())
                or ("10000" in compact and re.search(r"\b(for|while)\b", text.lower()))
            )
            handles_hangs = re.search(
                r"\b(timeout|alarm|deadline|poll|kill|terminate|communicate)\b",
                text.lower(),
            )
            if is_script and refers_to_target and covers_range and handles_hangs:
                candidates.append(path)

    assert candidates, (
        "No fuzzing script was found that targets processor, iterates through "
        "the 1..10000 range, and includes deadlock/timeout handling."
    )


def test_processor_fixed_exists_and_is_executable_elf():
    assert os.path.isfile(FIXED), f"The file {FIXED} does not exist."
    assert os.access(FIXED, os.X_OK), f"The file {FIXED} is not executable."
    with open(FIXED, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The file {FIXED} is not an ELF executable."


def test_processor_fixed_original_cases():
    run_processor(FIXED, [8492], timeout=3.0)
    run_processor(FIXED, [10, 20, 30], timeout=3.0)


def test_fixed_source_compiles_and_both_artifacts_handle_derived_inputs():
    assert os.path.isfile(SOURCE), f"The fixed source file {SOURCE} does not exist."

    build_dir = tempfile.mkdtemp(prefix="verify_processor_")
    rebuilt = os.path.join(build_dir, "processor_from_submitted_source")
    compiled = subprocess.run(
        ["gcc", "-pthread", "-O2", "-o", rebuilt, SOURCE],
        capture_output=True,
        text=True,
        check=False,
    )
    assert compiled.returncode == 0, (
        "The submitted processor.c does not compile with gcc -pthread:\n"
        + compiled.stdout + compiled.stderr
    )

    rng = secrets.SystemRandom()
    cases = [
        [TRIGGER],
        [10, 20, 30],
        [rng.randint(1, 10000)],
        [rng.randint(1, 10000) for _ in range(rng.randint(4, 12))],
        [rng.randint(1, 10000), TRIGGER, rng.randint(1, 10000)],
        [rng.randint(1, 10000) for _ in range(40)],
    ]
    for values in cases:
        run_processor(FIXED, values)
        run_processor(rebuilt, values)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
