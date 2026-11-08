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
import zlib

WORKSPACE_DIR = "/home/user/api_workspace"
PAYLOAD_FILE = os.path.join(WORKSPACE_DIR, "payload.dat")
API_TESTER_FILE = os.path.join(WORKSPACE_DIR, "api_tester.c")
BUILD_SH_FILE = os.path.join(WORKSPACE_DIR, "build.sh")
RUN_TESTS_SH_FILE = os.path.join(WORKSPACE_DIR, "run_tests.sh")
BINARY_FILE = os.path.join(WORKSPACE_DIR, "api_tester")
LOG_FILE = "/home/user/test_results.log"


def get_expected_crc32(path=PAYLOAD_FILE):
    with open(path, "rb") as f:
        data = f.read()
    crc = zlib.crc32(data) & 0xFFFFFFFF
    return f"{crc:08x}"


def run_checked(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, timeout=20, **kwargs)


def test_payload_not_modified():
    assert os.path.isfile(PAYLOAD_FILE), f"Payload file {PAYLOAD_FILE} is missing."
    with open(PAYLOAD_FILE, "r") as f:
        content = f.read()
    assert content == "INTEGRATION_TEST_PAYLOAD_V1", "payload.dat was modified, which is forbidden."


def test_build_sh_fixed():
    assert os.path.isfile(BUILD_SH_FILE), f"{BUILD_SH_FILE} is missing."
    with open(BUILD_SH_FILE, "r") as f:
        content = f.read()
    assert "-lz" in content, f"{BUILD_SH_FILE} does not link zlib (-lz). The build will fail."


def test_run_tests_sh_exists_and_executable():
    assert os.path.isfile(RUN_TESTS_SH_FILE), f"{RUN_TESTS_SH_FILE} was not created."
    assert os.access(RUN_TESTS_SH_FILE, os.X_OK), f"{RUN_TESTS_SH_FILE} does not have executable permissions."


def test_repaired_c_source_is_memory_safe_and_correct():
    assert os.path.isfile(API_TESTER_FILE), f"{API_TESTER_FILE} is missing."
    with tempfile.TemporaryDirectory() as td:
        sanitized_binary = os.path.join(td, "api_tester_sanitized")
        compile_result = run_checked([
            "gcc", "-O0", "-g", "-Wall", "-Wextra",
            "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-no-pie",
            API_TESTER_FILE, "-o", sanitized_binary, "-lz"
        ], cwd=WORKSPACE_DIR)
        assert compile_result.returncode == 0, (
            "api_tester.c did not compile with memory-safety instrumentation.\n"
            f"stdout: {compile_result.stdout}\nstderr: {compile_result.stderr}"
        )

        samples = [
            b"independent verifier input\x00with binary data\n",
            os.urandom(8193),
        ]
        for index, data in enumerate(samples):
            input_path = os.path.join(td, f"input_{index}.dat")
            with open(input_path, "wb") as f:
                f.write(data)
            expected = f"{zlib.crc32(data) & 0xFFFFFFFF:08x}\n"
            env = os.environ.copy()
            env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
            env["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1"
            result = run_checked([sanitized_binary, input_path], cwd=WORKSPACE_DIR, env=env)
            assert result.returncode == 0, (
                "The repaired C program crashed or triggered a memory-safety error.\n"
                f"stdout: {result.stdout}\nstderr: {result.stderr}"
            )
            assert result.stdout == expected, (
                f"The repaired C program returned {result.stdout!r}, expected {expected!r}."
            )


def test_build_script_compiles_api_tester_source():
    with open(API_TESTER_FILE, "rb") as f:
        original_source = f.read()
    source_mode = stat.S_IMODE(os.stat(API_TESTER_FILE).st_mode)
    sentinel = secrets.token_hex(4)
    probe_source = (
        '#include <stdio.h>\n'
        'int main(void) { puts("' + sentinel + '"); return 0; }\n'
    ).encode()

    try:
        with open(API_TESTER_FILE, "wb") as f:
            f.write(probe_source)
        if os.path.lexists(BINARY_FILE):
            os.remove(BINARY_FILE)
        result = run_checked(["./build.sh"], cwd=WORKSPACE_DIR)
        assert result.returncode == 0, (
            f"build.sh failed.\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert os.path.isfile(BINARY_FILE) and os.access(BINARY_FILE, os.X_OK), (
            "build.sh did not create an executable named api_tester."
        )
        with open(BINARY_FILE, "rb") as f:
            assert f.read(4) == b"\x7fELF", "api_tester is not a compiled executable."
        probe = run_checked(["./api_tester"], cwd=WORKSPACE_DIR)
        assert probe.returncode == 0 and probe.stdout == sentinel + "\n", (
            "build.sh did not compile the current api_tester.c source into api_tester."
        )
    finally:
        with open(API_TESTER_FILE, "wb") as f:
            f.write(original_source)
        os.chmod(API_TESTER_FILE, source_mode)
        if os.path.lexists(BINARY_FILE):
            os.remove(BINARY_FILE)

    result = run_checked(["./build.sh"], cwd=WORKSPACE_DIR)
    assert result.returncode == 0, (
        "build.sh could not compile the repaired source.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(BINARY_FILE) and os.access(BINARY_FILE, os.X_OK)
    with open(BINARY_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "api_tester is not a compiled executable."

    with tempfile.NamedTemporaryFile(dir=WORKSPACE_DIR, delete=False) as f:
        data = os.urandom(3073)
        f.write(data)
        input_path = f.name
    try:
        expected = f"{zlib.crc32(data) & 0xFFFFFFFF:08x}\n"
        result = run_checked(["./api_tester", input_path], cwd=WORKSPACE_DIR)
        assert result.returncode == 0, f"Built api_tester failed: {result.stderr}"
        assert result.stdout == expected, (
            f"Built api_tester returned {result.stdout!r}, expected {expected!r}."
        )
    finally:
        os.remove(input_path)


def test_execution_and_results():
    # Remove log file if it exists to ensure we are testing the script's creation of it
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)

    # Run the student's script
    result = subprocess.run(
        ["./run_tests.sh"],
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"run_tests.sh failed with return code {result.returncode}.\nStderr: {result.stderr}"

    assert os.path.isfile(LOG_FILE), f"{LOG_FILE} was not created by run_tests.sh."

    with open(LOG_FILE, "r") as f:
        actual_content = f.read().strip()

    expected_checksum = get_expected_crc32()
    assert actual_content == expected_checksum, (
        f"The test results log should contain ONLY the checksum '{expected_checksum}', "
        f"but found '{actual_content}'."
    )


def test_run_tests_invokes_build_and_generated_api_tester():
    sentinel = secrets.token_hex(4)
    build_marker = os.path.join("/tmp", "build_called_" + secrets.token_hex(12))
    tester_marker = os.path.join("/tmp", "tester_called_" + secrets.token_hex(12))

    def snapshot(path):
        if not os.path.lexists(path):
            return None
        with open(path, "rb") as f:
            return (f.read(), stat.S_IMODE(os.stat(path).st_mode))

    def restore(path, saved):
        if saved is None:
            if os.path.lexists(path):
                os.remove(path)
        else:
            with open(path, "wb") as f:
                f.write(saved[0])
            os.chmod(path, saved[1])

    saved_build = snapshot(BUILD_SH_FILE)
    saved_binary = snapshot(BINARY_FILE)
    saved_log = snapshot(LOG_FILE)
    instrumented_build = f'''#!/bin/bash
set -e
printf called > {build_marker!r}
cat > api_tester <<'PROBE_EOF'
#!/bin/bash
if [ "$#" -ne 1 ] || [ "$1" != "payload.dat" ]; then
    exit 42
fi
printf called > {tester_marker!r}
printf '%s\\n' '{sentinel}'
PROBE_EOF
chmod +x api_tester
'''

    try:
        with open(BUILD_SH_FILE, "w") as f:
            f.write(instrumented_build)
        os.chmod(BUILD_SH_FILE, 0o755)
        if os.path.lexists(BINARY_FILE):
            os.remove(BINARY_FILE)
        if os.path.lexists(LOG_FILE):
            os.remove(LOG_FILE)

        result = run_checked(["./run_tests.sh"], cwd=WORKSPACE_DIR)
        assert result.returncode == 0, (
            f"run_tests.sh failed under execution tracing.\nstderr: {result.stderr}"
        )
        assert os.path.isfile(build_marker), "run_tests.sh did not execute ./build.sh."
        assert os.path.isfile(tester_marker), (
            "run_tests.sh did not execute the api_tester produced by build.sh with payload.dat."
        )
        assert os.path.isfile(LOG_FILE), f"{LOG_FILE} was not created."
        with open(LOG_FILE, "r") as f:
            logged = f.read()
        assert logged == sentinel + "\n", (
            "run_tests.sh did not capture api_tester's standard output directly into the log."
        )
        assert re.fullmatch(r"[0-9a-f]{8}\n", logged)
    finally:
        restore(BUILD_SH_FILE, saved_build)
        restore(BINARY_FILE, saved_binary)
        restore(LOG_FILE, saved_log)
        for marker in (build_marker, tester_marker):
            if os.path.exists(marker):
                os.remove(marker)

    test_payload_not_modified()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
