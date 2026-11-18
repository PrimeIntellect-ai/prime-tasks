#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import shutil
import subprocess
import tempfile
import pytest

SOURCE = "/home/user/src/verifier.c"
EXECUTABLE = "/home/user/bin/verifier"
ARTIFACT_DIR = "/home/user/artifacts"
REPORT = "/home/user/verified_checksums.json"


def checksum_bytes(data):
    checksum = 0x12345678
    for value in data:
        checksum ^= value
        checksum = ((checksum << 1) & 0xFFFFFFFF) | (checksum >> 31)
    return f"{checksum:08x}"


def calc_expected_checksum(size, fill):
    return checksum_bytes(bytes([fill]) * size)


def expected_stdout(path, data):
    return f"{os.path.basename(path)}: {checksum_bytes(data)}\n"


def run_verifier(executable, path, env=None):
    result = subprocess.run(
        [executable, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        env=env,
    )
    assert result.returncode == 0, (
        f"{executable} failed for {path} with exit code {result.returncode}: "
        f"{result.stderr}"
    )
    return result


def test_verifier_c_fixed():
    filepath = SOURCE
    assert os.path.isfile(filepath), f"Source file {filepath} is missing"

    with open(filepath, "r") as f:
        content = f.read()

    # Preserve the original source-level checks.
    assert "i <= length" not in content, "Bug 1 (loop boundary) was not fixed in verifier.c"
    assert content.count("free(buffer);") == 1, "Bug 2 (double free) was not fixed in verifier.c, or buffer is not freed exactly once"


def test_executable_exists():
    filepath = EXECUTABLE
    assert os.path.isfile(filepath), f"Executable {filepath} is missing"
    assert os.access(filepath, os.X_OK), f"File {filepath} is not executable"
    with open(filepath, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{filepath} must be a compiled executable"


def test_source_is_memory_safe_and_functional():
    sanitized = os.path.join(tempfile.mkdtemp(prefix="verifier-build-"), "verifier-sanitized")
    build = subprocess.run(
        [
            "gcc", "-std=c11", "-Wall", "-Wextra", "-O1", "-g",
            "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
            SOURCE, "-o", sanitized,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"verifier.c does not compile cleanly: {build.stderr}"

    cases = [
        b"",
        b"\x00",
        b"\xff",
        bytes(range(256)),
        secrets.token_bytes(997),
        secrets.token_bytes(8193),
    ]
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "halt_on_error=1:abort_on_error=1:detect_leaks=1"
    env["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1"

    with tempfile.TemporaryDirectory(prefix="verifier-inputs-") as directory:
        for index, data in enumerate(cases):
            path = os.path.join(directory, f"case_{index}_{secrets.token_hex(5)}.bin")
            with open(path, "wb") as f:
                f.write(data)
            result = run_verifier(sanitized, path, env)
            assert result.stdout == expected_stdout(path, data), (
                f"Sanitized verifier produced incorrect output for {path}: {result.stdout!r}"
            )


def test_installed_verifier_on_unpredictable_inputs():
    cases = [secrets.token_bytes(3), secrets.token_bytes(511), secrets.token_bytes(4097)]
    with tempfile.TemporaryDirectory(prefix="installed-verifier-") as directory:
        for data in cases:
            path = os.path.join(directory, f"dynamic_{secrets.token_hex(8)}.bin")
            with open(path, "wb") as f:
                f.write(data)
            result = run_verifier(EXECUTABLE, path)
            assert result.stdout == expected_stdout(path, data), (
                f"Installed verifier produced incorrect output for {path}: {result.stdout!r}"
            )


def test_packaging_script_exists():
    scripts = glob.glob("/home/user/package_artifacts.*")
    assert len(scripts) > 0, "Packaging script /home/user/package_artifacts.* is missing"


def packaging_command(path):
    if path.endswith(".sh"):
        return ["bash", path]
    if path.endswith(".py"):
        return ["python3", path]
    if path.endswith(".js"):
        node = shutil.which("node")
        assert node is not None, "A Node packaging script was supplied but Node.js is unavailable"
        return [node, path]
    raise AssertionError(f"Unsupported packaging script type: {path}")


def validate_report_for_current_artifacts():
    assert os.path.isfile(REPORT), f"JSON report {REPORT} is missing"
    with open(REPORT, "r") as f:
        data = json.load(f)
    assert isinstance(data, dict), "JSON root must be an object (dictionary)"

    artifact_paths = sorted(glob.glob(os.path.join(ARTIFACT_DIR, "*.bin")))
    for path in artifact_paths:
        with open(path, "rb") as f:
            expected = checksum_bytes(f.read())
        name = os.path.basename(path)
        assert name in data, f"Packaging report is missing dynamically tested artifact {name}"
        assert isinstance(data[name], str), f"Report value for {name} must be a hexadecimal string"
        assert data[name] == expected, (
            f"Packaging report checksum for {name} is incorrect: expected {expected}, got {data[name]!r}"
        )
    return artifact_paths


def test_packaging_script_executes_verifier_for_all_bin_files():
    candidates = [
        path for path in (
            "/home/user/package_artifacts.sh",
            "/home/user/package_artifacts.py",
            "/home/user/package_artifacts.js",
        ) if os.path.isfile(path)
    ]
    assert candidates, "No supported packaging script was found"

    dynamic_name = f"audit_{secrets.token_hex(10)}.bin"
    dynamic_path = os.path.join(ARTIFACT_DIR, dynamic_name)
    with open(dynamic_path, "wb") as f:
        f.write(secrets.token_bytes(1379))

    real_executable = EXECUTABLE + f".audit-real-{secrets.token_hex(6)}"
    call_log = f"/tmp/verifier-calls-{secrets.token_hex(8)}.log"
    os.replace(EXECUTABLE, real_executable)
    wrapper = (
        "#!/bin/sh\n"
        f"printf '%s\\n' \"$@\" >> {call_log!r}\n"
        f"exec {real_executable!r} \"$@\"\n"
    )
    with open(EXECUTABLE, "w") as f:
        f.write(wrapper)
    os.chmod(EXECUTABLE, 0o755)

    failures = []
    success = False
    try:
        for script in candidates:
            if os.path.exists(call_log):
                os.unlink(call_log)
            if os.path.exists(REPORT):
                os.unlink(REPORT)
            try:
                result = subprocess.run(
                    packaging_command(script),
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=90,
                )
                assert result.returncode == 0, (
                    f"Packaging script exited with {result.returncode}: {result.stderr}"
                )
                artifact_paths = validate_report_for_current_artifacts()
                assert os.path.isfile(call_log), "Packaging script did not run /home/user/bin/verifier"
                with open(call_log, "r") as f:
                    called = {os.path.realpath(line.strip()) for line in f if line.strip()}
                missing = [path for path in artifact_paths if os.path.realpath(path) not in called]
                assert not missing, f"Packaging script did not run the verifier on: {missing}"
                success = True
                break
            except Exception as exc:
                failures.append(f"{script}: {exc}")
        assert success, "No packaging script successfully processed all artifacts. " + "; ".join(failures)
    finally:
        if os.path.exists(EXECUTABLE):
            os.unlink(EXECUTABLE)
        os.replace(real_executable, EXECUTABLE)


def test_verified_checksums_json():
    filepath = REPORT
    assert os.path.isfile(filepath), f"JSON report {filepath} is missing"

    with open(filepath, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{filepath} is not a valid JSON file")

    expected_checksums = {
        "app_v1.bin": calc_expected_checksum(1024, 0xAA),
        "app_v2.bin": calc_expected_checksum(2048, 0xBB),
        "app_v3.bin": calc_expected_checksum(512, 0xCC)
    }

    assert isinstance(data, dict), "JSON root must be an object (dictionary)"

    for filename, expected_hex in expected_checksums.items():
        assert filename in data, f"Missing key '{filename}' in {filepath}"
        actual_hex = str(data[filename]).strip().lower()
        assert actual_hex == expected_hex.lower(), f"Checksum for {filename} is incorrect. Expected {expected_hex.lower()}, got {actual_hex}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
