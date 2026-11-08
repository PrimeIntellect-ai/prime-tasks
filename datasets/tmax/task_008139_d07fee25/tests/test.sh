#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shlex
import shutil
import subprocess


def test_cpp_fixed():
    path = "/home/user/audit_parser.cpp"
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original source assertion.
    assert "strcpy(buffer" not in content, "Vulnerable 'strcpy(buffer' is still present in the C++ code."


def test_executable_exists():
    path = "/home/user/audit_parser"
    assert os.path.isfile(path), f"Missing executable: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "audit_parser is not a compiled executable."


def test_run_audit_script():
    path = "/home/user/run_audit.sh"
    assert os.path.isfile(path), f"Missing script: {path}"
    assert os.access(path, os.X_OK), f"Script is not executable: {path}"

    with open(path, "r") as f:
        content = f.read()

    assert "bwrap" in content, "Script does not use 'bwrap'."
    assert "--unshare-all" in content, "Script does not contain '--unshare-all' flag for bwrap."
    assert re.search(r"--ro-bind\s+/\s+/", content), "Script does not contain '--ro-bind / /' for bwrap."


def test_output_generated():
    output_dir = "/home/user/audit_output"
    output_file = os.path.join(output_dir, "decrypted_trail.txt")

    assert os.path.isdir(output_dir), f"Missing directory: {output_dir}"
    assert os.path.isfile(output_file), f"Missing output file: {output_file}"

    with open(output_file, "r") as f:
        content = f.read()

    assert "AUDIT_RECORD:" in content, "Output file does not contain the expected decrypted audit records."
    assert len(content.strip()) > 0, "Output file is empty."


def _has_triplet(args, option, source, destination):
    return any(args[i:i + 3] == [option, source, destination]
               for i in range(max(0, len(args) - 2)))


def test_compiled_source_and_real_sandboxed_execution():
    source = "/home/user/audit_parser.cpp"
    submitted_binary = "/home/user/audit_parser"
    script = "/home/user/run_audit.sh"
    encrypted_path = "/home/user/encrypted_logs.dat"
    output_dir = "/home/user/audit_output"
    output_path = os.path.join(output_dir, "decrypted_trail.txt")
    key_path = "/home/user/key.txt"

    with open(key_path, "r") as f:
        key = f.read().strip()
    assert re.fullmatch(r"[0-9a-fA-F]{64}", key), "Invalid test key."

    token = secrets.token_hex(24)
    lines = [
        "LONG-" + token + "-" + ("A" * 20000),
        "SECOND-" + token + "-" + ("B" * 10000),
    ]
    plaintext = "\n".join(lines)
    expected = "".join("AUDIT_RECORD: " + line + "\n" for line in lines)

    test_binary = "/tmp/audit_parser_from_source"
    source_output = "/tmp/audit_parser_source_output.txt"
    plain_path = "/tmp/audit_plaintext.txt"
    cipher_path = "/tmp/audit_ciphertext.bin"
    iv = os.urandom(16)

    with open(plain_path, "wb") as f:
        f.write(plaintext.encode("ascii"))

    subprocess.run([
        "g++", "-std=c++17", "-fsanitize=address", "-fno-omit-frame-pointer",
        source, "-o", test_binary, "-lcrypto"
    ], check=True, timeout=60)

    subprocess.run([
        "openssl", "enc", "-aes-256-cbc", "-K", key, "-iv", iv.hex(),
        "-in", plain_path, "-out", cipher_path
    ], check=True, timeout=30)

    with open(cipher_path, "rb") as f:
        encrypted_test_data = iv + f.read()

    original_encrypted_data = None
    if os.path.exists(encrypted_path):
        with open(encrypted_path, "rb") as f:
            original_encrypted_data = f.read()

    # First compile and exercise the submitted source under ASan. Exact output
    # ensures long records are preserved rather than merely truncated.
    with open(encrypted_path, "wb") as f:
        f.write(encrypted_test_data)
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=0:abort_on_error=1"
    subprocess.run(
        [test_binary, encrypted_path, source_output, key],
        check=True, timeout=30, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    with open(source_output, "r") as f:
        assert f.read() == expected, "Compiled source did not safely preserve long audit records."

    bwrap = shutil.which("bwrap")
    assert bwrap, "bubblewrap is not installed."
    real_bwrap_path = os.path.realpath(bwrap)
    saved_bwrap_path = real_bwrap_path + ".verifier-real"
    invocation_log = "/tmp/verifier_bwrap_invocations.jsonl"
    if os.path.exists(invocation_log):
        os.unlink(invocation_log)
    assert not os.path.exists(saved_bwrap_path), "Unexpected saved bwrap path already exists."

    os.rename(real_bwrap_path, saved_bwrap_path)
    wrapper = """#!/bin/bash
python3 - \"$@\" >> {log} <<'PY'
import json
import sys
print(json.dumps(sys.argv[1:]))
PY
exec {real} \"$@\"
""".format(log=shlex.quote(invocation_log), real=shlex.quote(saved_bwrap_path))
    with open(real_bwrap_path, "w") as f:
        f.write(wrapper)
    os.chmod(real_bwrap_path, 0o755)

    try:
        os.makedirs(output_dir, exist_ok=True)
        if os.path.exists(output_path):
            os.unlink(output_path)
        with open(encrypted_path, "wb") as f:
            f.write(encrypted_test_data)

        result = subprocess.run(
            [script], timeout=45, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        assert result.returncode == 0, (
            f"run_audit.sh failed with exit code {result.returncode}: {result.stderr}"
        )
        assert os.path.isfile(output_path), "run_audit.sh did not generate decrypted_trail.txt."
        with open(output_path, "r") as f:
            actual = f.read()
        assert actual == expected, "Sandboxed parser output did not match the dynamically generated long records."

        assert os.path.isfile(invocation_log), "run_audit.sh did not actually invoke the installed bwrap."
        with open(invocation_log, "r") as f:
            invocations = [json.loads(line) for line in f if line.strip()]

        required_command = [submitted_binary, encrypted_path, output_path, key]
        valid = False
        for args in invocations:
            if "--unshare-all" not in args:
                continue
            if not _has_triplet(args, "--ro-bind", "/", "/"):
                continue
            if not _has_triplet(args, "--bind", output_dir, output_dir):
                continue
            if args[-4:] != required_command:
                continue
            valid = True
            break
        assert valid, (
            "No bwrap invocation used --unshare-all, --ro-bind / /, the required "
            "read-write --bind for audit_output, and the required parser command."
        )
    finally:
        if os.path.exists(real_bwrap_path):
            os.unlink(real_bwrap_path)
        if os.path.exists(saved_bwrap_path):
            os.rename(saved_bwrap_path, real_bwrap_path)
        if original_encrypted_data is not None:
            with open(encrypted_path, "wb") as f:
                f.write(original_encrypted_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
