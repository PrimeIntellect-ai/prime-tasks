#!/bin/bash
set -u
mkdir -p /logs/verifier

SERVER_PID=""
cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

run_checks() {
    local ROOT=/home/user/AudioStreamer
    local CFILTER="$ROOT/c_filter"
    local RUST="$ROOT/rust_server"
    local SCRIPT="$ROOT/process_stream.sh"
    local OUTPUT=/home/user/processed_output.wav
    local INPUT=/app/test_audio.wav
    local EXPECTED=/tests/golden_processed.wav
    local CMAKE_BUILD=/tmp/audio_filter_verifier_build

    test -d "$CFILTER" || return 1
    test -d "$RUST" || return 1
    test -f "$CFILTER/CMakeLists.txt" || return 1
    test -f "$RUST/Cargo.toml" || return 1
    test -f "$RUST/build.rs" || return 1
    test -f "$RUST/src/main.rs" || return 1
    test -f "$SCRIPT" || return 1
    test -f "$INPUT" || return 1
    test -f "$EXPECTED" || return 1
    bash -n "$SCRIPT" || return 1

    rm -rf "$CMAKE_BUILD"
    cmake -S "$CFILTER" -B "$CMAKE_BUILD" >/tmp/verifier_cmake_configure.log 2>&1 || return 1
    cmake --build "$CMAKE_BUILD" >/tmp/verifier_cmake_build.log 2>&1 || return 1
    find "$CMAKE_BUILD" -type f -name 'libaudiofilter.so*' | grep -q . || return 1

    cd "$RUST" || return 1
    cargo clean >/tmp/verifier_cargo_clean.log 2>&1 || return 1
    cargo build --release >/tmp/verifier_cargo_build.log 2>&1 || return 1

    local BIN
    BIN=$(python3 - <<'PY'
import json
import os
import subprocess
m = json.loads(subprocess.check_output(["cargo", "metadata", "--format-version", "1", "--no-deps"], text=True))
for package in m["packages"]:
    for target in package["targets"]:
        if "bin" in target.get("kind", []):
            print(os.path.join(m["target_directory"], "release", target["name"]))
            raise SystemExit(0)
raise SystemExit(1)
PY
) || return 1
    test -x "$BIN" || return 1
    readelf -d "$BIN" 2>/dev/null | grep -Eq 'libaudiofilter\.so' || return 1

    # Stop any server left by the agent so the tested connection must reach the
    # freshly rebuilt binary above.
    python3 - <<'PY'
import os
import signal
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        fields = line.split()
        if fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
            inodes.add(fields[9])
for entry in os.listdir("/proc"):
    if not entry.isdigit() or int(entry) == os.getpid():
        continue
    fd_dir = f"/proc/{entry}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                os.kill(int(entry), signal.SIGTERM)
                break
    except OSError:
        pass
PY
    sleep 0.3

    (cd "$RUST" && exec "$BIN") >/tmp/verifier_server.log 2>&1 &
    SERVER_PID=$!
    local ready=0
    for _ in $(seq 1 50); do
        kill -0 "$SERVER_PID" 2>/dev/null || return 1
        if nc -z 127.0.0.1 8080 >/dev/null 2>&1; then
            ready=1
            break
        fi
        sleep 0.1
    done
    test "$ready" -eq 1 || return 1

    rm -f "$OUTPUT"
    if timeout 5 bash "$SCRIPT" /tmp/definitely_missing_audio_fixture.wav >/tmp/verifier_missing.log 2>&1; then
        return 1
    fi
    rm -f "$OUTPUT"

    local start_ns end_ns elapsed_ns minimum_ns size
    size=$(stat -c %s "$INPUT") || return 1
    start_ns=$(date +%s%N)
    timeout 20 bash "$SCRIPT" "$INPUT" >/tmp/verifier_client.log 2>&1 || return 1
    end_ns=$(date +%s%N)
    elapsed_ns=$((end_ns - start_ns))
    minimum_ns=$((size * 1000000000 / 51200 * 9 / 10))
    if [ "$elapsed_ns" -lt "$minimum_ns" ]; then
        echo "Transfer completed too quickly for a 50 KB/s limit: ${elapsed_ns}ns" >&2
        return 1
    fi

    kill -0 "$SERVER_PID" 2>/dev/null || return 1

    cat <<'TEST_EOF' >/tmp/test_final_state.py
import os
import wave
import numpy as np
import pytest

def read_wav(path):
    with wave.open(path, 'rb') as w:
        frames = w.readframes(w.getnframes())
        return np.frombuffer(frames, dtype=np.int16)

def test_processed_output_exists():
    output_path = "/home/user/processed_output.wav"
    assert os.path.exists(output_path), f"Processed output file {output_path} does not exist. The bash script must generate this file."

def test_audio_mse():
    actual_path = "/home/user/processed_output.wav"
    expected_path = "/tests/golden_processed.wav"

    assert os.path.exists(actual_path), f"Output file {actual_path} is missing."
    assert os.path.exists(expected_path), f"Golden file {expected_path} is missing."

    try:
        actual = read_wav(actual_path)
    except Exception as e:
        pytest.fail(f"Failed to read actual output as a WAV file: {e}")

    try:
        expected = read_wav(expected_path)
    except Exception as e:
        pytest.fail(f"Failed to read golden output as a WAV file: {e}")

    # Preserve the original MSE assertion.
    min_len = min(len(actual), len(expected))
    actual_trimmed = actual[:min_len]
    expected_trimmed = expected[:min_len]

    if min_len == 0:
        pytest.fail("One of the audio files has 0 frames.")

    mse = np.mean((actual_trimmed.astype(np.float32) - expected_trimmed.astype(np.float32)) ** 2)
    assert mse <= 0.001, f"Audio MSE is {mse}, which exceeds the threshold of 0.001. The output audio does not match the expected filter output."

    # The stream must be complete, not merely a matching prefix.
    assert len(actual) == len(expected), "Processed audio has an incorrect frame count."
    with open(actual_path, "rb") as a, open(expected_path, "rb") as e:
        assert a.read() == e.read(), "Processed WAV is not an exact copy of the complete server response."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
