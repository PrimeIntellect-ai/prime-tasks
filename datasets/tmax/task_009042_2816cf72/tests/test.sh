#!/bin/bash
mkdir -p /logs/verifier

run_checks() {
    service=/home/user/ingestd_service
    source_file="$service/ingest.c"
    binary="$service/ingestd"
    verify="$service/verify.sh"

    test -f "$source_file" && test ! -L "$source_file" || return 1
    test -f "$binary" && test ! -L "$binary" && test -x "$binary" || return 1
    test -f "$verify" && test ! -L "$verify" || return 1

    # Ensure the provided verification script was not modified.
    cat << 'VERIFY_EOF' > /tmp/expected_verify.sh
#!/bin/bash
cd /home/user/ingestd_service

# Test 1: Buffer overflow test
./ingestd "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "FAILED: Buffer overflow test crashed." > /home/user/verification.log
    exit 1
fi

# Test 2: Infinite loop test (timeout after 2 seconds)
timeout 2s ./ingestd "seg1,,seg2" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "FAILED: Infinite loop test hung or crashed." > /home/user/verification.log
    exit 1
fi

echo "ALL TESTS PASSED" > /home/user/verification.log
VERIFY_EOF
    cmp -s /tmp/expected_verify.sh "$verify" || return 1

    # Check that the submitted artifact is a rebuilt ELF with the expected
    # source-level symbols and debug information, and is not older than source.
    python3 - << 'PY' || return 1
import os
src = "/home/user/ingestd_service/ingest.c"
binpath = "/home/user/ingestd_service/ingestd"
with open(binpath, "rb") as f:
    assert f.read(4) == b"\x7fELF", "ingestd is not an ELF binary"
assert os.stat(binpath).st_mtime_ns >= os.stat(src).st_mtime_ns, \
    "ingestd is older than ingest.c; recompile the repaired source"
PY
    nm "$binary" 2>/dev/null | grep -Eq '[[:space:]]process_segments$' || return 1
    nm "$binary" 2>/dev/null | grep -Eq '[[:space:]]parse_log$' || return 1
    readelf -S "$binary" 2>/dev/null | grep -q '\.debug_info' || return 1

    # Exercise the binary supplied by the agent on additional boundary and
    # empty-segment cases, rather than trusting verification.log.
    python3 - "$binary" << 'PY' || return 1
import subprocess, sys
binary = sys.argv[1]
cases = [
    "A" * n for n in (0, 1, 62, 63, 64, 65, 66, 127, 256, 4096)
] + [
    ",", ",,", ",,,", "seg1,,seg2", ",seg1", "seg1,",
    "a,,,b", "a,,b,,c", ",a,,b,", "x," * 100 + ",y",
]
for payload in cases:
    try:
        result = subprocess.run(
            [binary, payload], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=2, check=False
        )
    except subprocess.TimeoutExpired:
        raise AssertionError(f"ingestd hung for payload {payload[:80]!r}")
    assert result.returncode == 0, (
        f"ingestd exited {result.returncode} for payload {payload[:80]!r}: "
        f"{result.stderr.decode(errors='replace')[:300]}"
    )
    assert result.stdout.decode(errors="replace").strip() == "SUCCESS"
PY

    # Rebuild the submitted source with AddressSanitizer and exercise it too.
    # This ties the behavioral checks to ingest.c and reliably detects the
    # off-by-one write even when an unsanitized build happens not to crash.
    gcc -g -O0 -fsanitize=address -fno-omit-frame-pointer \
        "$source_file" -o /tmp/ingestd_sanitized || return 1
    python3 - /tmp/ingestd_sanitized << 'PY' || return 1
import os, subprocess, sys
binary = sys.argv[1]
env = os.environ.copy()
env["ASAN_OPTIONS"] = "abort_on_error=1:detect_leaks=0"
cases = [
    "B" * n for n in (62, 63, 64, 65, 66, 128, 1024)
] + [
    ",", ",,", ",,,", "left,,right", ",left", "right,",
    "a,,,b", ",a,,b,", "one,,two,,,three",
]
for payload in cases:
    try:
        result = subprocess.run(
            [binary, payload], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=2, env=env, check=False
        )
    except subprocess.TimeoutExpired:
        raise AssertionError(f"sanitized source build hung for {payload[:80]!r}")
    assert result.returncode == 0, (
        f"sanitized source build failed for {payload[:80]!r}: "
        f"{result.stderr.decode(errors='replace')[:500]}"
    )
    assert result.stdout.decode(errors="replace").strip() == "SUCCESS"
PY

    # Invoke the unmodified provided script and require it to create the log.
    rm -f /home/user/verification.log
    timeout 15s bash "$verify" || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

def test_token_recovered():
    token_file = "/home/user/token.txt"
    assert os.path.isfile(token_file), f"File {token_file} does not exist. The token was not saved."
    with open(token_file, "r") as f:
        token_content = f.read().strip()
    expected_token = "SRE_MONITOR_TOK_99281aB"
    assert token_content == expected_token, f"The token in {token_file} is incorrect. Found: '{token_content}', Expected: '{expected_token}'"

def test_verification_passed():
    log_file = "/home/user/verification.log"
    assert os.path.isfile(log_file), f"File {log_file} does not exist. Did you run verify.sh?"
    with open(log_file, "r") as f:
        log_content = f.read().strip()
    expected_log = "ALL TESTS PASSED"
    assert log_content == expected_log, f"The verification log indicates failure or is incorrect. Found: '{log_content}'"
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
