#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import re
import secrets
import shutil
import stat
import subprocess
import tempfile

BUILD_DIR = "/home/user/build"
AMD64_BIN = os.path.join(BUILD_DIR, "gateway_amd64")
ARM64_BIN = os.path.join(BUILD_DIR, "gateway_arm64")
HASHES_FILE = os.path.join(BUILD_DIR, "hashes.txt")
STRESS_GO = "/home/user/gateway/tests/stress.go"
MAIN_C = "/home/user/gateway/main.c"


def run_binary(path, argument=None, runner=None):
    command = ([runner, "-L", "/usr/aarch64-linux-gnu", path] if runner else [path])
    if argument is not None:
        command.append(argument)
    return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)


def expected_decode(value):
    output = bytearray()
    i = 0
    raw = value.encode("ascii")
    while i < len(raw):
        if i + 2 < len(raw) and raw[i] == ord("%"):
            pair = raw[i + 1:i + 3]
            try:
                output.append(int(pair.decode("ascii"), 16))
                i += 3
                continue
            except ValueError:
                pass
        output.append(raw[i])
        i += 1
    return bytes(output)


def test_build_directory_and_binaries_exist():
    assert os.path.isdir(BUILD_DIR), f"Build directory {BUILD_DIR} does not exist."
    assert os.path.isfile(AMD64_BIN), f"Binary {AMD64_BIN} does not exist."
    assert os.path.isfile(ARM64_BIN), f"Binary {ARM64_BIN} does not exist."


def test_amd64_secure_mode():
    result = subprocess.run([AMD64_BIN], capture_output=True, text=True)
    assert result.returncode == 0, f"{AMD64_BIN} exited with code {result.returncode}, expected 0."
    assert "INSECURE" not in result.stdout, f"{AMD64_BIN} was not compiled with -DSECURE_MODE."


def test_arm64_architecture():
    result = subprocess.run(["file", ARM64_BIN], capture_output=True, text=True)
    assert "aarch64" in result.stdout.lower() or "arm64" in result.stdout.lower(), \
        f"{ARM64_BIN} does not appear to be an ARM64 binary: {result.stdout}"


def test_urldecode_functionality():
    fixed = {
        "hello%20world": b"hello world",
        "incomplete%": b"incomplete%",
        "invalid%ZZ": b"invalid%ZZ",
    }
    for value, expected in fixed.items():
        result = run_binary(AMD64_BIN, value)
        assert result.returncode == 0
        assert result.stdout == expected + b"\n", f"Failed to decode {value!r}: {result.stdout!r}"

    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/ "
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    cases = []
    for _ in range(35):
        raw = "".join(rng.choice(alphabet) for _ in range(rng.randint(8, 90)))
        encoded = "".join(
            f"%{ord(ch):02X}" if rng.random() < 0.55 else ch
            for ch in raw
        )
        if rng.random() < 0.7:
            bad = rng.choice(["%", "%G1", "%1G", "%zz"])
            pos = rng.randrange(len(encoded) + 1)
            encoded = encoded[:pos] + bad + encoded[pos:]
        cases.append(encoded)
    cases.append("%41" * 50000 + "%tail")

    for value in cases:
        result = run_binary(AMD64_BIN, value)
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert result.stdout == expected_decode(value) + b"\n", f"Incorrect decoding for generated input {value[:120]!r}"


def _arm_disassembly(path, symbol):
    result = subprocess.run(
        ["aarch64-linux-gnu-objdump", "--no-show-raw-insn", f"--disassemble={symbol}", path],
        capture_output=True, text=True, check=True
    )
    lines = []
    inside = False
    for line in result.stdout.splitlines():
        if re.search(rf"<{re.escape(symbol)}>:$", line.strip()):
            inside = True
            continue
        if inside:
            if not line.strip():
                continue
            if re.match(r"^[0-9a-fA-F]+ <[^>]+>:$", line.strip()):
                break
            line = re.sub(r"^\s*[0-9a-fA-F]+:\s*", "", line)
            line = re.sub(r"\b[0-9a-fA-F]+\s+<([^>]+)>", r"<\1>", line)
            if line.strip():
                lines.append(line.strip())
    return lines


def test_arm64_secure_mode_and_decoding():
    qemu = shutil.which("qemu-aarch64") or shutil.which("qemu-aarch64-static")
    if qemu:
        no_args = run_binary(ARM64_BIN, runner=qemu)
        assert no_args.returncode == 0
        assert b"INSECURE" not in no_args.stdout
        dynamic_cases = [
            "arm%20payload%2F" + secrets.token_hex(8),
            secrets.token_hex(10) + "%GZ%25%41",
            "%7E%2e%2E%2f" + secrets.token_hex(7) + "%",
        ]
        for value in dynamic_cases:
            result = run_binary(ARM64_BIN, value, qemu)
            assert result.returncode == 0
            assert result.stdout == expected_decode(value) + b"\n"
        return

    strings = subprocess.run(["strings", ARM64_BIN], capture_output=True, text=True, check=True)
    assert "INSECURE" not in strings.stdout, "ARM64 binary contains the non-SECURE_MODE branch."

    # If no ARM emulator is installed, compare the submitted ARM machine code for
    # main and decode_url with independently cross-compiled SECURE_MODE variants.
    submitted = (_arm_disassembly(ARM64_BIN, "main"), _arm_disassembly(ARM64_BIN, "decode_url"))
    assert submitted[0] and submitted[1], "ARM64 binary lacks main or decode_url code."
    matched = False
    with tempfile.TemporaryDirectory() as directory:
        for index, optimization in enumerate([None, "-O0", "-O1", "-O2", "-O3", "-Os"]):
            reference = os.path.join(directory, f"reference-{index}")
            command = ["aarch64-linux-gnu-gcc", "-DSECURE_MODE"]
            if optimization:
                command.append(optimization)
            command.extend([MAIN_C, "-o", reference])
            subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            candidate = (_arm_disassembly(reference, "main"), _arm_disassembly(reference, "decode_url"))
            if candidate == submitted:
                matched = True
                break
    assert matched, "ARM64 main/decode_url machine code does not match a SECURE_MODE build of the repaired source."


def _write_stress_wrapper(path, real_path, state_path):
    wrapper = f'''#!/bin/bash
STATE={state_path!r}
REAL={real_path!r}
N=$(python3 - "$STATE" "${{1-}}" <<'PY'
import fcntl, json, sys
path, payload = sys.argv[1], sys.argv[2]
with open(path + ".lock", "a+") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        with open(path) as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        data = {{"calls": 0, "active": 0, "maximum": 0, "payloads": []}}
    data["calls"] += 1
    data["active"] += 1
    data["maximum"] = max(data["maximum"], data["active"])
    data["payloads"].append(payload)
    with open(path, "w") as f:
        json.dump(data, f)
    print(data["calls"])
PY
)
cleanup() {{
python3 - "$STATE" <<'PY'
import fcntl, json, sys
path = sys.argv[1]
with open(path + ".lock", "a+") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    with open(path) as f:
        data = json.load(f)
    data["active"] -= 1
    with open(path, "w") as f:
        json.dump(data, f)
PY
}}
trap cleanup EXIT
sleep 0.10
if [[ "${{STRESS_FORCE_FAILURE-}}" = "1" && "$N" = "1" ]]; then
    exit 73
fi
"$REAL" "$@"
exit $?
'''
    with open(path, "w") as file:
        file.write(wrapper)
    os.chmod(path, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                   stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)


def _run_stress(state_path, force_failure=False):
    with open(state_path, "w") as file:
        json.dump({"calls": 0, "active": 0, "maximum": 0, "payloads": []}, file)
    environment = os.environ.copy()
    if force_failure:
        environment["STRESS_FORCE_FAILURE"] = "1"
    result = subprocess.run(
        ["go", "run", STRESS_GO], cwd="/home/user/gateway",
        capture_output=True, text=True, timeout=90, env=environment
    )
    with open(state_path) as file:
        state = json.load(file)
    return result, state


def test_stress_go_concurrency():
    assert os.path.isfile(STRESS_GO), f"{STRESS_GO} does not exist."
    with open(STRESS_GO, "r") as f:
        content = f.read()
    assert "go " in content, "stress.go does not use goroutines ('go ' keyword missing)."
    assert "sync.WaitGroup" in content or "chan " in content, \
        "stress.go does not use sync.WaitGroup or channels for concurrency synchronization."
    assert "100" in content, "stress.go does not appear to run 100 times."

    real_path = AMD64_BIN + ".verifier-real"
    state_path = "/tmp/stress-verifier-state.json"
    assert not os.path.exists(real_path)
    os.replace(AMD64_BIN, real_path)
    try:
        _write_stress_wrapper(AMD64_BIN, real_path, state_path)
        success, state = _run_stress(state_path)
        assert success.returncode == 0, success.stderr
        assert "PASS" in success.stdout.splitlines(), "Stress test did not print PASS after all successful executions."
        assert state["calls"] == 100, f"Stress test executed the binary {state['calls']} times instead of 100."
        assert state["maximum"] >= 2, "The 100 executions were not concurrent."
        assert len(set(state["payloads"])) >= 2, "Stress test did not use various payloads."

        failure, failed_state = _run_stress(state_path, force_failure=True)
        assert failed_state["calls"] == 100, "Stress test did not execute all 100 runs when one failed."
        assert "PASS" not in failure.stdout.splitlines(), "Stress test printed PASS even though an execution failed."
    finally:
        if os.path.exists(AMD64_BIN):
            os.unlink(AMD64_BIN)
        os.replace(real_path, AMD64_BIN)
        for suffix in ("", ".lock"):
            try:
                os.unlink(state_path + suffix)
            except FileNotFoundError:
                pass


def test_hashes_file():
    assert os.path.isfile(HASHES_FILE), f"Hashes file {HASHES_FILE} does not exist."
    with open(HASHES_FILE, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert len(lines) == 2, f"Expected 2 lines in {HASHES_FILE}, found {len(lines)}."
    content = "\n".join(lines)
    assert "gateway_amd64" in content, "gateway_amd64 missing from hashes.txt"
    assert "gateway_arm64" in content, "gateway_arm64 missing from hashes.txt"
    with open(AMD64_BIN, "rb") as f:
        amd64_hash = hashlib.sha256(f.read()).hexdigest()
    with open(ARM64_BIN, "rb") as f:
        arm64_hash = hashlib.sha256(f.read()).hexdigest()
    assert amd64_hash in content, f"Correct SHA256 for gateway_amd64 ({amd64_hash}) not found in hashes.txt"
    assert arm64_hash in content, f"Correct SHA256 for gateway_arm64 ({arm64_hash}) not found in hashes.txt"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
