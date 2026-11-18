#!/bin/bash
set +e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

REAL_DECODER="/tmp/telemetry_decoder.real.$$"
WRAPPER_BIN="/tmp/telemetry_decoder.wrapper.$$"
CALL_LOG="/logs/verifier/decoder_calls.bin"

cleanup() {
    if [ -e "$REAL_DECODER" ]; then
        rm -f /app/telemetry_decoder
        mv "$REAL_DECODER" /app/telemetry_decoder
    fi
    rm -f "$WRAPPER_BIN"
}
trap cleanup EXIT

cat > /tmp/telemetry_decoder_wrapper.c <<EOF
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <openssl/md5.h>

#define REAL_DECODER "$REAL_DECODER"
#define CALL_LOG "$CALL_LOG"

int main(void) {
    unsigned char input[2048];
    size_t used = 0;

    while (used < sizeof(input)) {
        ssize_t n = read(STDIN_FILENO, input + used, sizeof(input) - used);
        if (n == 0) break;
        if (n < 0) {
            if (errno == EINTR) continue;
            return 120;
        }
        used += (size_t)n;
    }

    unsigned char digest[MD5_DIGEST_LENGTH];
    MD5(input, used, digest);

    unsigned char record[4 + MD5_DIGEST_LENGTH];
    uint32_t length = (uint32_t)used;
    record[0] = (unsigned char)(length & 0xff);
    record[1] = (unsigned char)((length >> 8) & 0xff);
    record[2] = (unsigned char)((length >> 16) & 0xff);
    record[3] = (unsigned char)((length >> 24) & 0xff);
    memcpy(record + 4, digest, MD5_DIGEST_LENGTH);

    int logfd = open(CALL_LOG, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (logfd < 0) return 121;
    ssize_t written;
    do {
        written = write(logfd, record, sizeof(record));
    } while (written < 0 && errno == EINTR);
    close(logfd);
    if (written != (ssize_t)sizeof(record)) return 122;

    int pipefd[2];
    if (pipe(pipefd) != 0) return 123;

    size_t offset = 0;
    while (offset < used) {
        ssize_t n = write(pipefd[1], input + offset, used - offset);
        if (n < 0) {
            if (errno == EINTR) continue;
            return 124;
        }
        offset += (size_t)n;
    }
    close(pipefd[1]);

    if (dup2(pipefd[0], STDIN_FILENO) < 0) return 125;
    close(pipefd[0]);

    execl(REAL_DECODER, REAL_DECODER, (char *)NULL);
    return 126;
}
EOF

if ! gcc -O2 /tmp/telemetry_decoder_wrapper.c -o "$WRAPPER_BIN" -lcrypto -Wno-deprecated-declarations; then
    exit 0
fi
if ! mv /app/telemetry_decoder "$REAL_DECODER"; then
    exit 0
fi
if ! cp "$WRAPPER_BIN" /app/telemetry_decoder; then
    exit 0
fi
chmod 0555 /app/telemetry_decoder
: > "$CALL_LOG"
chmod 0600 "$CALL_LOG"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import hashlib
import json
import os
import struct
import subprocess
import time
import pytest


def load_expected():
    raw_path = "/home/user/data/raw_telemetry.bin"
    expected = {}
    expected_calls = collections.Counter()
    total_records = 0

    with open(raw_path, "rb") as f:
        while True:
            header = f.read(8)
            if not header:
                break
            assert len(header) == 8, "Truncated telemetry record header"
            record_id, length = struct.unpack("<II", header)
            payload = f.read(length)
            assert len(payload) == length, f"Truncated payload for record {record_id}"
            total_records += 1

            if length > 512 or payload.startswith(b"\xDE\xAD"):
                continue

            digest = hashlib.md5(payload).hexdigest()
            expected[str(record_id)] = digest
            expected_calls[(length, bytes.fromhex(digest))] += 1

    assert total_records == 10000, f"Expected 10000 input records, got {total_records}"
    return expected, expected_calls


def load_decoder_calls(path):
    with open(path, "rb") as f:
        raw = f.read()
    assert len(raw) % 20 == 0, "Decoder invocation log is malformed"

    calls = collections.Counter()
    for offset in range(0, len(raw), 20):
        length = struct.unpack_from("<I", raw, offset)[0]
        digest = raw[offset + 4:offset + 20]
        calls[(length, digest)] += 1
    return calls


def test_telemetry_pipeline():
    telemetry_dir = "/home/user/telemetry"

    # 1. Build the Go application
    build_res = subprocess.run(
        ["go", "build"],
        cwd=telemetry_dir,
        capture_output=True,
        text=True,
    )
    assert build_res.returncode == 0, f"Go build failed:\n{build_res.stderr}"

    # Ensure binary exists
    binary_path = os.path.join(telemetry_dir, "telemetry")
    assert os.path.exists(binary_path), "Compiled binary 'telemetry' not found."

    # Remove existing output.json if any, to ensure we test the fresh run
    output_path = os.path.join(telemetry_dir, "output.json")
    if os.path.exists(output_path):
        os.remove(output_path)

    call_log = "/logs/verifier/decoder_calls.bin"
    with open(call_log, "wb"):
        pass

    # 2. Execute the compiled binary and measure time
    start_time = time.time()
    exec_res = subprocess.run(
        ["./telemetry"],
        cwd=telemetry_dir,
        capture_output=True,
        text=True,
    )
    duration = time.time() - start_time

    assert exec_res.returncode == 0, f"Execution of ./telemetry failed:\n{exec_res.stderr}"

    # 3. Check execution time threshold
    assert duration <= 3.0, f"Metric failed: Execution took {duration:.2f}s (Threshold <= 3.0s)"

    # 4. Check output.json
    assert os.path.exists(output_path), f"Output file not found at {output_path}"

    try:
        with open(output_path, "r") as f:
            data = json.load(f)
    except Exception as e:
        pytest.fail(f"Failed to load JSON from {output_path}: {e}")

    assert isinstance(data, dict), "output.json must contain a JSON map"

    # 5. Verify the number of records (validates race condition fix and proper filtering)
    expected_records = 9300
    actual_records = len(data)
    assert actual_records == expected_records, f"Expected {expected_records} valid records, got {actual_records}"

    # Verify every record ID and decoder output against values derived from the input.
    expected, expected_calls = load_expected()
    assert len(expected) == expected_records
    assert data == expected, "output.json contains incorrect record IDs or decoder outputs"

    # Verify each valid payload was actually sent to the legacy decoder, and no poison
    # payload or substitute payload was sent.
    actual_calls = load_decoder_calls(call_log)
    assert actual_calls == expected_calls, "The decoder was not invoked exactly once with every valid payload"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
