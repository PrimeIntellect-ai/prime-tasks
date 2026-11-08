#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shlex
import subprocess
import tempfile
import uuid
import pytest


def test_extractor_cpp_exists():
    """Check that the C++ source file exists."""
    path = "/home/user/extractor.cpp"
    assert os.path.isfile(path), f"File {path} does not exist."


def test_extractor_executable_exists():
    """Check that the compiled extractor exists and is executable."""
    path = "/home/user/extractor"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled executable."


def test_process_sh_exists_and_executable():
    """Check that the bash script exists and is executable."""
    path = "/home/user/process.sh"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_top_cpu_csv_contents():
    """Check that top_cpu.csv contains the correct top 5 records."""
    path = "/home/user/top_cpu.csv"
    assert os.path.isfile(path), f"File {path} does not exist."

    expected_lines = [
        "1696151040,srv-04,99",
        "1696151280,srv-04,95",
        "1696150860,srv-02,92",
        "1696150920,srv-01,88",
        "1696151160,srv-05,78"
    ]

    with open(path, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_lines, f"Contents of {path} do not match the expected output. Got: {actual_lines}"


def test_cron_configuration():
    """Check that telemetry.cron contains the correct cron expression."""
    path = "/home/user/telemetry.cron"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    pattern = r"^0\s+\*\s+\*\s+\*\s+\*\s+/bin/bash\s+/home/user/process\.sh"

    found = False
    for line in content.splitlines():
        if re.match(pattern, line.strip()):
            found = True
            break

    assert found, f"Cron expression for process.sh at minute 0 not found in {path}."


def make_random_records(count=9):
    rng = secrets.SystemRandom()
    cpus = rng.sample(range(1, 100), count)
    base = rng.randrange(1800000000, 2000000000)
    records = []
    for i, cpu in enumerate(cpus):
        timestamp = str(base + i * rng.randrange(17, 113))
        hostname = "host-" + uuid.uuid4().hex[:10]
        raw = f"Event {uuid.uuid4().hex[:8]} | Mem:{rng.randrange(1, 129)}GB | CPU:{cpu}% | status ok"
        records.append((timestamp, hostname, raw, cpu))
    rng.shuffle(records)
    return records


def input_and_expected(records):
    input_text = "".join(f"{ts},{host},{raw}\n" for ts, host, raw, cpu in records)
    normalized = "".join(f"{ts},{host},{cpu}\n" for ts, host, raw, cpu in records)
    return input_text, normalized


def run_extractor(path, input_text):
    result = subprocess.run(
        [path], input=input_text, text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, f"Extractor failed: {result.stderr}"
    return result.stdout


def test_extractor_and_cpp_source_on_generated_input():
    records = make_random_records()
    input_text, expected = input_and_expected(records)

    actual = run_extractor("/home/user/extractor", input_text)
    assert actual == expected, f"Installed extractor produced incorrect output: {actual!r}"

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "extractor-from-source")
        build = subprocess.run(
            ["g++", "-std=c++17", "/home/user/extractor.cpp", "-o", rebuilt],
            text=True, capture_output=True, timeout=30
        )
        assert build.returncode == 0, f"extractor.cpp did not compile: {build.stderr}"
        rebuilt_actual = run_extractor(rebuilt, input_text)
        assert rebuilt_actual == expected, f"Extractor rebuilt from source produced incorrect output: {rebuilt_actual!r}"


def test_process_pipeline_on_generated_telemetry():
    telemetry = "/home/user/telemetry.csv"
    output = "/home/user/top_cpu.csv"
    extractor = "/home/user/extractor"
    process_script = "/home/user/process.sh"

    with open(process_script, "r") as f:
        script_content = f.read()
    assert "/home/user/extractor" in script_content, "process.sh does not reference /home/user/extractor."

    records = make_random_records(11)
    input_text, _ = input_and_expected(records)
    expected_lines = [
        f"{ts},{host},{cpu}"
        for ts, host, raw, cpu in sorted(records, key=lambda row: row[3], reverse=True)[:5]
    ]

    telemetry_bytes = open(telemetry, "rb").read()
    telemetry_mode = os.stat(telemetry).st_mode
    output_existed = os.path.exists(output)
    output_bytes = open(output, "rb").read() if output_existed else None
    output_mode = os.stat(output).st_mode if output_existed else None

    token = uuid.uuid4().hex
    real_extractor = f"/tmp/extractor-real-{token}"
    marker = f"/tmp/extractor-called-{token}"
    os.replace(extractor, real_extractor)
    with open(extractor, "w") as f:
        f.write("#!/bin/bash\n")
        f.write(f"printf x >> {shlex.quote(marker)}\n")
        f.write(f"exec {shlex.quote(real_extractor)} \"$@\"\n")
    os.chmod(extractor, 0o755)

    result = None
    actual_lines = None
    called = False
    try:
        with open(telemetry, "w") as f:
            f.write(input_text)
        result = subprocess.run(
            ["/bin/bash", process_script], text=True, capture_output=True, timeout=15
        )
        called = os.path.isfile(marker) and os.path.getsize(marker) > 0
        if os.path.isfile(output):
            with open(output, "r") as f:
                actual_lines = [line.strip() for line in f if line.strip()]
    finally:
        if os.path.exists(extractor):
            os.remove(extractor)
        os.replace(real_extractor, extractor)
        if os.path.exists(marker):
            os.remove(marker)
        with open(telemetry, "wb") as f:
            f.write(telemetry_bytes)
        os.chmod(telemetry, telemetry_mode)
        if output_existed:
            with open(output, "wb") as f:
                f.write(output_bytes)
            os.chmod(output, output_mode)
        elif os.path.exists(output):
            os.remove(output)

    assert result.returncode == 0, f"process.sh failed: {result.stderr}"
    assert called, "process.sh did not invoke /home/user/extractor."
    assert actual_lines == expected_lines, f"Pipeline output was incorrect. Got: {actual_lines}, expected: {expected_lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
