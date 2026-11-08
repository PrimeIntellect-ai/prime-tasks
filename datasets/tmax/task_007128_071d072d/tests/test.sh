#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import stat
import subprocess
import tempfile
import uuid


def test_malicious_files_log():
    log_path = "/home/user/malicious_files.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."

    # Compute expected files and hashes
    expected_lines = []
    base_dir = "/home/user"
    exclude_dir = "/home/user/data"

    for root, dirs, files in os.walk(base_dir):
        if root.startswith(exclude_dir):
            continue
        for file in files:
            if file.endswith(".txt"):
                filepath = os.path.join(root, file)
                with open(filepath, "rb") as f:
                    file_hash = hashlib.sha256(f.read()).hexdigest()
                expected_lines.append(f"{file_hash}  {filepath}")

    expected_lines.sort()

    with open(log_path, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_lines, "The contents of malicious_files.log do not match the expected sorted sha256sum output."


def test_binary_exists_and_permissions():
    binary_path = "/home/user/processor_secure"
    assert os.path.isfile(binary_path), f"{binary_path} does not exist."

    st = os.stat(binary_path)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o750, f"Permissions for {binary_path} are {oct(permissions)}, expected 0o750."

    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary_path} is not a compiled ELF executable."


def test_binary_blocks_traversal_dotdot():
    binary_path = "/home/user/processor_secure"
    target_file = "/home/user/test_traversal.txt"

    if os.path.exists(target_file):
        os.remove(target_file)

    result = subprocess.run(
        [binary_path, "../test_traversal.txt", "malicious_content"],
        capture_output=True,
        text=True
    )

    assert result.returncode == 1, f"Expected exit code 1 for path traversal attempt, got {result.returncode}."
    assert result.stderr == "Invalid filename\n", f"Expected stderr 'Invalid filename\\n', got {repr(result.stderr)}."
    assert not os.path.exists(target_file), "The binary wrote the file despite the path traversal attempt."


def test_binary_blocks_traversal_slash():
    binary_path = "/home/user/processor_secure"

    result = subprocess.run(
        [binary_path, "sub/dir.txt", "malicious_content"],
        capture_output=True,
        text=True
    )

    assert result.returncode == 1, f"Expected exit code 1 for path containing '/', got {result.returncode}."
    assert result.stderr == "Invalid filename\n", f"Expected stderr 'Invalid filename\\n', got {repr(result.stderr)}."


def test_binary_allows_safe():
    binary_path = "/home/user/processor_secure"
    safe_target = "/home/user/data/safe_test_file.txt"

    if os.path.exists(safe_target):
        os.remove(safe_target)

    result = subprocess.run(
        [binary_path, "safe_test_file.txt", "safe_content"],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"Expected exit code 0 for safe filename, got {result.returncode}."
    assert os.path.isfile(safe_target), "The binary did not create the safe file."

    with open(safe_target, "r") as f:
        content = f.read()

    assert content == "safe_content", "The binary did not write the correct content to the safe file."


def exercise_required_behavior(executable, tag):
    token = uuid.uuid4().hex

    # This contains '..' but no slash, so rejecting slashes alone cannot pass.
    dotdot_name = f"audit_{token}..{tag}.txt"
    dotdot_target = os.path.join("/home/user/data", dotdot_name)
    if os.path.exists(dotdot_target):
        os.remove(dotdot_target)

    result = subprocess.run(
        [executable, dotdot_name, "must_not_be_written"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 1, f"{executable} did not reject a filename containing '..'."
    assert result.stderr == "Invalid filename\n", f"{executable} emitted incorrect stderr for '..': {result.stderr!r}"
    assert not os.path.exists(dotdot_target), f"{executable} wrote a filename containing '..'."

    slash_name = f"audit_{token}/child_{tag}.txt"
    result = subprocess.run(
        [executable, slash_name, "must_not_be_written"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 1, f"{executable} did not reject a filename containing '/'."
    assert result.stderr == "Invalid filename\n", f"{executable} emitted incorrect stderr for '/': {result.stderr!r}"

    safe_name = f"audit.{token}.{tag}.txt"
    safe_target = os.path.join("/home/user/data", safe_name)
    if os.path.exists(safe_target):
        os.remove(safe_target)

    result = subprocess.run(
        [executable, safe_name, f"safe-{token}"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, f"{executable} rejected a safe filename."
    assert os.path.isfile(safe_target), f"{executable} did not create the safe file."
    with open(safe_target, "r") as f:
        assert f.read() == f"safe-{token}", f"{executable} wrote incorrect safe-file content."


def test_patched_source_compiles_and_matches_required_behavior():
    source_path = "/home/user/upload_processor.c"
    binary_path = "/home/user/processor_secure"
    assert os.path.isfile(source_path), f"{source_path} does not exist."

    # A final binary older than the submitted source was not compiled from the
    # final patched source state.
    assert os.stat(binary_path).st_mtime_ns >= os.stat(source_path).st_mtime_ns, \
        "processor_secure is older than upload_processor.c; recompile the patched source."

    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt = os.path.join(temp_dir, "processor_from_submitted_source")
        compile_result = subprocess.run(
            ["gcc", source_path, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, \
            f"The submitted upload_processor.c does not compile: {compile_result.stderr}"

        exercise_required_behavior(rebuilt, "source")

    # Exercise the delivered ELF on independently generated names as well.
    exercise_required_behavior(binary_path, "binary")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
