#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import shutil
import stat
import subprocess
import tempfile

PROJECT = "/home/user/project"
LIBRARY = f"{PROJECT}/c_src/build/libvalidator.so"
BINARY = f"{PROJECT}/rust_src/target/release/rust_api"
SCRIPT = f"{PROJECT}/benchmark.sh"
LOG = f"{PROJECT}/slowest_times.log"
OUTPUT_RE = re.compile(r"Result: (-?\d+), Time: (\d+) us")


def test_validator_c_fixed():
    path = f"{PROJECT}/c_src/validator.c"
    assert os.path.isfile(path), f"{path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert 'visibility("hidden")' not in content, "validator.c still contains visibility('hidden')"


def test_c_library_built_and_loadable():
    assert os.path.isfile(LIBRARY), f"{LIBRARY} was not built."
    with open(LIBRARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{LIBRARY} is not an ELF shared library."

    try:
        library = ctypes.CDLL(LIBRARY)
        validate = library.validate_request
    except (OSError, AttributeError) as exc:
        raise AssertionError(f"Could not dynamically load exported validate_request: {exc}")

    validate.argtypes = [ctypes.c_int]
    validate.restype = ctypes.c_int
    assert validate(42) == 1, "validate_request(42) did not return 1."
    assert validate(0) == 0, "validate_request(0) did not return 0."


def test_rust_binary_built_and_runs():
    assert os.path.isfile(BINARY), f"{BINARY} was not built."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF executable."

    dynamic = subprocess.run(
        ["readelf", "-d", BINARY], text=True, capture_output=True, timeout=10
    )
    assert dynamic.returncode == 0, f"readelf failed for {BINARY}: {dynamic.stderr}"
    assert "libvalidator.so" in dynamic.stdout, "Rust binary is not dynamically linked to libvalidator.so."

    run = subprocess.run([BINARY, "42"], text=True, capture_output=True, timeout=10)
    assert run.returncode == 0, f"Rust binary failed: {run.stderr}"
    match = OUTPUT_RE.fullmatch(run.stdout.strip())
    assert match, f"Unexpected Rust output: {run.stdout!r}"
    assert int(match.group(1)) == 1, "Rust binary did not report Result: 1 for client ID 42."


def test_benchmark_script_exists():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist."


def test_slowest_times_log():
    assert os.path.isfile(LOG), f"{LOG} does not exist."
    with open(LOG, "r") as f:
        content = f.read().strip()

    if not content:
        assert False, f"{LOG} is empty."

    lines = content.split('\n')
    assert len(lines) == 5, f"Expected exactly 5 lines in {LOG}, got {len(lines)}"

    times = []
    for line in lines:
        assert line.isdigit(), f"Line '{line}' in {LOG} is not a valid integer."
        times.append(int(line))

    assert times == sorted(times, reverse=True), f"Times in {LOG} are not sorted in descending order."


def test_benchmark_executes_binary_100_times_and_derives_log():
    tempdir = tempfile.mkdtemp(prefix="benchmark_verify_")
    real_binary = os.path.join(tempdir, "rust_api.real")
    calls_path = os.path.join(tempdir, "calls.log")
    outputs_path = os.path.join(tempdir, "outputs.log")
    original_mode = stat.S_IMODE(os.stat(BINARY).st_mode)

    os.replace(BINARY, real_binary)
    wrapper = f'''#!/bin/bash
printf '%s|%s\\n' "$#" "$*" >> {calls_path!r}
out="$({real_binary!r} "$@")"
printf '%s\\n' "$out" >> {outputs_path!r}
printf '%s\\n' "$out"
'''
    try:
        with open(BINARY, "w") as f:
            f.write(wrapper)
        os.chmod(BINARY, 0o755)

        run = subprocess.run(
            ["/bin/bash", SCRIPT],
            cwd=PROJECT,
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert run.returncode == 0, (
            f"benchmark.sh failed with status {run.returncode}.\n"
            f"stdout: {run.stdout}\nstderr: {run.stderr}"
        )

        with open(calls_path, "r") as f:
            calls = f.read().splitlines()
        assert len(calls) == 100, f"benchmark.sh executed the Rust binary {len(calls)} times, expected 100."
        assert all(call == "1|42" for call in calls), (
            "Every benchmark execution must pass 42 as the sole command-line argument."
        )

        with open(outputs_path, "r") as f:
            outputs = f.read().splitlines()
        assert len(outputs) == 100, "Could not capture exactly 100 Rust program outputs."

        observed_times = []
        for output in outputs:
            match = OUTPUT_RE.fullmatch(output)
            assert match, f"Rust execution produced malformed output: {output!r}"
            assert int(match.group(1)) == 1, f"Rust execution returned an unexpected result: {output!r}"
            observed_times.append(int(match.group(2)))

        assert os.path.isfile(LOG), f"{LOG} was not created by benchmark.sh."
        with open(LOG, "r") as f:
            raw_log = f.read()
        assert re.fullmatch(r"\d+\n\d+\n\d+\n\d+\n\d+\n?", raw_log), (
            f"{LOG} must contain exactly five clean integer lines."
        )
        actual = [int(line) for line in raw_log.splitlines()]
        expected = sorted(observed_times, reverse=True)[:5]
        assert actual == expected, (
            f"{LOG} does not contain the five slowest measured times. "
            f"Expected {expected}, got {actual}."
        )
    finally:
        if os.path.lexists(BINARY):
            os.remove(BINARY)
        if os.path.exists(real_binary):
            os.replace(real_binary, BINARY)
            os.chmod(BINARY, original_mode)
        shutil.rmtree(tempdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
