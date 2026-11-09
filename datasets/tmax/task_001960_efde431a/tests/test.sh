#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import shutil
import signal
import subprocess

import pytest

TOOL = pathlib.Path("/home/user/tool")
BINARY = TOOL / "http_fuzzer"
ARCHIVE = TOOL / "rust_parser/target/debug/librust_parser.a"
LOG = pathlib.Path("/home/user/test_result.log")


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


@pytest.fixture(scope="session", autouse=True)
def clean_build_from_submitted_sources():
    # Remove all potentially stale build products, then require the submitted
    # Makefile to recreate both the Rust archive and final executable.
    clean = run(["make", "clean"], cwd=TOOL)
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}\n{clean.stderr}"
    for path in (BINARY, TOOL / "main.o"):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
    shutil.rmtree(TOOL / "rust_parser/target", ignore_errors=True)

    build = run(["make"], cwd=TOOL, timeout=180)
    assert build.returncode == 0, f"Clean make failed:\n{build.stdout}\n{build.stderr}"
    assert ARCHIVE.is_file(), "Makefile did not build the Rust static archive"


def test_http_fuzzer_compiled():
    """Verify the http_fuzzer compiled successfully and is executable."""
    path = "/home/user/tool/http_fuzzer"
    assert os.path.isfile(path), f"Executable not found: {path}. The Makefile might still be broken or the build failed."
    assert os.access(path, os.X_OK), f"File is not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "http_fuzzer is not a compiled ELF executable"


def test_rust_static_library_and_export_are_linked():
    cargo_toml = (TOOL / "rust_parser/Cargo.toml").read_text()
    assert 'crate-type = ["staticlib"]' in cargo_toml, "Rust library must remain a static library"

    archive_type = run(["file", str(ARCHIVE)])
    assert archive_type.returncode == 0 and "archive" in archive_type.stdout.lower(), archive_type.stdout

    archive_symbols = run(["nm", "-g", str(ARCHIVE)])
    assert archive_symbols.returncode == 0
    assert "get_fuzz_payload" in archive_symbols.stdout, "Rust archive does not export get_fuzz_payload"

    binary_symbols = run(["nm", "-g", str(BINARY)])
    assert binary_symbols.returncode == 0
    assert "get_fuzz_payload" in binary_symbols.stdout, "Rust payload function was not linked into http_fuzzer"

    dynamic = run(["ldd", str(BINARY)])
    assert dynamic.returncode == 0, dynamic.stderr
    assert "rust_parser" not in dynamic.stdout, "Rust parser was dynamically linked instead of statically linked"


def test_rust_payload_has_static_null_terminated_storage():
    # Call the submitted Rust archive directly many times and retain the first
    # pointer while applying allocation pressure. This detects the original
    # dangling String pointer rather than trusting text in a log.
    probe_source = pathlib.Path("/tmp/payload_probe.c")
    probe_binary = pathlib.Path("/tmp/payload_probe")
    probe_source.write_text(r'''#include <stdlib.h>
#include <string.h>
#include <stdint.h>
extern const char *get_fuzz_payload(void);
int main(void) {
    const char *first = get_fuzz_payload();
    if (!first || strcmp(first, "FUZZ_PAYLOAD_X99") != 0) return 10;
    for (int i = 0; i < 1000; ++i) {
        char *p = malloc(4096);
        if (!p) return 11;
        memset(p, i, 4096);
        const char *next = get_fuzz_payload();
        if (next != first) return 12;
        if (strcmp(first, "FUZZ_PAYLOAD_X99") != 0) return 13;
        free(p);
    }
    return first[16] == '\0' ? 0 : 14;
}
''')
    compile_probe = run([
        "gcc", "-o", str(probe_binary), str(probe_source), str(ARCHIVE),
        "-lpthread", "-ldl", "-lm", "-lrt", "-lutil"
    ], timeout=60)
    assert compile_probe.returncode == 0, f"Could not link against Rust archive:\n{compile_probe.stderr}"
    probe = run([str(probe_binary)], timeout=15)
    assert probe.returncode == 0, f"Rust payload probe failed with status {probe.returncode}"


def test_compiled_fuzzer_execution():
    result = run([str(BINARY)], timeout=15)
    assert result.returncode == 0, f"http_fuzzer exited with {result.returncode}: {result.stderr}"
    assert result.stdout == "Fuzzer sending payload: FUZZ_PAYLOAD_X99\n", (
        f"Unexpected executable output: {result.stdout!r}"
    )


def test_test_result_log_exists():
    """Verify the E2E test script output was redirected to test_result.log."""
    path = "/home/user/test_result.log"
    assert os.path.isfile(path), f"Log file not found: {path}. Did you run the e2e_test.sh script and redirect its output?"


def test_test_result_log_content_payload():
    """Check that the log contains the successfully returned string from the Rust binary."""
    path = "/home/user/test_result.log"
    assert os.path.exists(path), f"Cannot check content because {path} does not exist."
    content = pathlib.Path(path).read_text()
    expected_str = "Fuzzer sending payload: FUZZ_PAYLOAD_X99"
    assert expected_str in content, f"Log does not contain expected payload output. The Rust bug might not be correctly fixed. Expected to find: '{expected_str}'"


def test_test_result_log_content_success():
    """Check that the log contains the completion string."""
    path = "/home/user/test_result.log"
    assert os.path.exists(path), f"Cannot check content because {path} does not exist."
    content = pathlib.Path(path).read_text()
    expected_str = "E2E Test Complete. Success!"
    assert expected_str in content, f"Log does not contain the success message. The E2E script may have failed. Expected to find: '{expected_str}'"


def test_e2e_script_really_runs_and_matches_saved_log():
    script = TOOL / "e2e_test.sh"
    assert script.is_file() and os.access(script, os.X_OK), "e2e_test.sh is missing or not executable"

    proc = subprocess.Popen(
        [str(script)], cwd=TOOL, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=20)
        returncode = proc.returncode
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        stdout, stderr = proc.communicate()
        pytest.fail(f"E2E script timed out. stdout={stdout!r}, stderr={stderr!r}")
    finally:
        # Remove any server left behind by a defective orchestration script.
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    assert returncode == 0, f"E2E script failed with {returncode}:\nstdout={stdout}\nstderr={stderr}"
    assert "Starting mock backend..." in stdout
    assert "Configuring reverse proxy (socat)..." in stdout
    assert "Running fuzzer against reverse proxy..." in stdout
    assert "Fuzzer sending payload: FUZZ_PAYLOAD_X99" in stdout
    assert "E2E Test Complete. Success!" in stdout

    # A genuine prior run redirected to the requested log has the same
    # deterministic standard output as this independently executed run.
    assert LOG.read_text().strip() == stdout.strip(), (
        "test_result.log is not the standard output produced by the E2E script"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
