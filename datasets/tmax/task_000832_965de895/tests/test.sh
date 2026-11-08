#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import stat
import subprocess
import tempfile
import pytest

LOG_PATH = "/home/user/redirect_logs.txt"
RECOVERED_PATH = "/home/user/recovered_pins.txt"
SEARCH_ROOTS = ["/home/user", "/tmp", "/app", "/root"]


def load_expected():
    assert os.path.exists(LOG_PATH), f"Original log file {LOG_PATH} is missing."
    rows = []
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        for line_no, raw in enumerate(f, 1):
            line = raw.rstrip("\r\n")
            assert line, f"Blank line in original log at line {line_no}."
            parts = line.split(',')
            assert len(parts) == 2, f"Invalid original log line {line_no}."
            rows.append((parts[0], parts[1]))
    assert rows, "Original log file is empty or invalid."
    return rows


def valid_recovery_bytes(data, expected):
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return False
    lines = text.splitlines()
    if len(lines) != len(expected) or any(not line for line in lines):
        return False
    recovered = []
    for line in lines:
        parts = line.split(',')
        if len(parts) != 2:
            return False
        thumb, pin = parts
        if re.fullmatch(r"[0-9]{4}", pin) is None:
            return False
        recovered.append((thumb, pin))
    if len({thumb for thumb, _ in recovered}) != len(recovered):
        return False
    if [thumb for thumb, _ in recovered] != [thumb for thumb, _ in expected]:
        return False
    for (thumb, pin), (_, token) in zip(recovered, expected):
        if hashlib.md5(f"{thumb}:{pin}".encode("utf-8")).hexdigest() != token:
            return False
    return True


def walk_agent_files():
    seen = set()
    for root in SEARCH_ROOTS:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if not os.path.islink(os.path.join(dirpath, d))]
            for name in filenames:
                path = os.path.join(dirpath, name)
                if path in seen or os.path.islink(path):
                    continue
                seen.add(path)
                yield path


def is_elf_executable(path):
    if os.path.realpath(path) == "/app/token_gen":
        return False
    try:
        mode = os.stat(path).st_mode
        if not stat.S_ISREG(mode) or mode & 0o111 == 0:
            return False
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def test_recovered_pins_accuracy_and_format():
    expected_lines = load_expected()
    assert os.path.exists(RECOVERED_PATH), f"Recovered PINs file {RECOVERED_PATH} is missing."

    try:
        with open(RECOVERED_PATH, "rb") as f:
            recovered_data = f.read()
    except Exception as e:
        pytest.fail(f"Could not read {RECOVERED_PATH}: {e}")

    assert valid_recovery_bytes(recovered_data, expected_lines), (
        "Recovered output must contain exactly one unique thumbprint per input line, "
        "in input order, with a valid 4-digit PIN."
    )

    expected_dict = {k: v for k, v in expected_lines}
    assert len(expected_dict) > 0, "Original log file is empty or invalid."
    recovered_lines = [l.strip() for l in recovered_data.decode("utf-8").splitlines() if l.strip()]
    correct = 0
    for line in recovered_lines:
        try:
            parts = line.split(',')
            if len(parts) == 2:
                thumb, pin = parts
                if thumb in expected_dict:
                    target_hash = expected_dict[thumb]
                    test_str = f"{thumb}:{pin}".encode('utf-8')
                    if hashlib.md5(test_str).hexdigest() == target_hash:
                        correct += 1
        except Exception:
            pass

    accuracy = correct / len(expected_dict)
    assert accuracy >= 0.99, f"Accuracy {accuracy:.2%} is below the threshold of 99.0%. Correctly recovered {correct} out of {len(expected_dict)} PINs."


def test_compiled_c_cracker_can_generate_results():
    expected = load_expected()
    original_log_hash = hashlib.sha256(open(LOG_PATH, "rb").read()).digest()
    original_recovered = open(RECOVERED_PATH, "rb").read()

    files = list(walk_agent_files())
    c_sources = [p for p in files if p.endswith(".c") and os.path.getsize(p) <= 2_000_000]
    existing_executables = [p for p in files if is_elf_executable(p)]
    assert c_sources, "No C source file for the cracking tool was found."
    assert existing_executables, "No compiled ELF executable for the cracking tool was found."

    compiled = []
    build_dir = tempfile.mkdtemp(prefix="verify_c_cracker_")
    for index, source in enumerate(c_sources[:20]):
        output = os.path.join(build_dir, f"cracker_{index}")
        try:
            result = subprocess.run(
                ["gcc", "-O3", "-fopenmp", "-Wno-deprecated-declarations", source,
                 "-o", output, "-lcrypto", "-lssl", "-lpthread"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
            )
            if result.returncode == 0 and is_elf_executable(output):
                compiled.append(output)
        except (OSError, subprocess.TimeoutExpired):
            pass
    assert compiled, "The submitted C cracking source could not be compiled."

    candidates = existing_executables[:20] + compiled
    generated = False
    try:
        for candidate in candidates:
            for args_kind in ("input_output", "input", "none"):
                temp_output = os.path.join(build_dir, "generated.txt")
                for path in (temp_output, RECOVERED_PATH):
                    try:
                        os.unlink(path)
                    except FileNotFoundError:
                        pass

                if args_kind == "input_output":
                    command = [candidate, LOG_PATH, temp_output]
                elif args_kind == "input":
                    command = [candidate, LOG_PATH]
                else:
                    command = [candidate]

                try:
                    result = subprocess.run(
                        command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        timeout=30, cwd="/home/user"
                    )
                except (OSError, subprocess.TimeoutExpired):
                    continue

                outputs = [result.stdout]
                for path in (temp_output, RECOVERED_PATH):
                    try:
                        with open(path, "rb") as f:
                            outputs.append(f.read())
                    except OSError:
                        pass
                if result.returncode == 0 and any(valid_recovery_bytes(data, expected) for data in outputs):
                    generated = True
                    break
            if generated:
                break
    finally:
        with open(RECOVERED_PATH, "wb") as f:
            f.write(original_recovered)

    assert hashlib.sha256(open(LOG_PATH, "rb").read()).digest() == original_log_hash, "Original log file was modified."
    assert generated, "No submitted compiled C tool could regenerate the recovered PINs from the log."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
