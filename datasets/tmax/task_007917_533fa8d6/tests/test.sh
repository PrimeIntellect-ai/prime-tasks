#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import shutil
import stat
import subprocess
import tempfile

PROJECT_DIR = "/home/user/cracker"
ORIGINAL_HASH = hashlib.md5(b"4829AUDIT_SALT").hexdigest()


def run_cracker(project_dir, target_dir, timeout=120):
    env = os.environ.copy()
    env["CARGO_TARGET_DIR"] = target_dir
    return subprocess.run(
        ["cargo", "run", "--release", "--quiet"],
        cwd=project_dir,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def assert_output_contains_pin(result, pin):
    output = result.stdout + "\n" + result.stderr
    assert result.returncode == 0, (
        f"Rust cracker exited with status {result.returncode}. Output:\n{output}"
    )
    assert re.search(rf"(?<!\d){re.escape(pin)}(?!\d)", output), (
        f"Rust cracker did not report expected PIN {pin}. Output:\n{output}"
    )


def test_audit_report():
    report_path = "/home/user/audit_report.txt"
    assert os.path.isfile(report_path), f"Audit report {report_path} does not exist."

    with open(report_path, "r") as f:
        content = f.read().strip()

    assert content == "PIN: 4829", f"Audit report content is incorrect. Expected 'PIN: 4829', got '{content}'"


def test_flag_txt_content_and_permissions():
    flag_path = "/home/user/flag.txt"
    assert os.path.isfile(flag_path), f"Flag file {flag_path} does not exist."

    with open(flag_path, "r") as f:
        content = f.read()

    assert content == "CONFIDENTIAL_DATA_9921\n", "Flag file content is incorrect."

    st = os.stat(flag_path)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o400, f"Flag file permissions are incorrect. Expected 0400, got {oct(permissions)}"


def test_rust_project_exists():
    project_dir = "/home/user/cracker"
    assert os.path.isdir(project_dir), f"Rust project directory {project_dir} does not exist."

    cargo_toml = os.path.join(project_dir, "Cargo.toml")
    main_rs = os.path.join(project_dir, "src", "main.rs")

    assert os.path.isfile(cargo_toml), f"Cargo.toml not found in {project_dir}."
    assert os.path.isfile(main_rs), f"src/main.rs not found in {project_dir}."


def test_rust_cracker_builds_and_finds_real_pin():
    with tempfile.TemporaryDirectory(prefix="cracker-target-") as target_dir:
        result = run_cracker(PROJECT_DIR, target_dir)
    assert_output_contains_pin(result, "4829")


def test_rust_cracker_actually_bruteforces_md5_targets():
    # Rebuild isolated copies with verifier-derived target hashes. This prevents a
    # program that merely prints the known PIN from satisfying the Rust-tool task.
    test_pins = ["%04d" % int.from_bytes(os.urandom(2), "big") for _ in range(2)]
    test_pins[0] = "%04d" % (int.from_bytes(os.urandom(2), "big") % 1000)
    test_pins = ["%04d" % (int(pin) % 10000) for pin in test_pins]

    for pin in test_pins:
        dynamic_hash = hashlib.md5((pin + "AUDIT_SALT").encode()).hexdigest()
        with tempfile.TemporaryDirectory(prefix="cracker-test-") as work_dir:
            project_copy = os.path.join(work_dir, "cracker")
            shutil.copytree(
                PROJECT_DIR,
                project_copy,
                ignore=shutil.ignore_patterns("target", ".git"),
            )

            replacements = 0
            for root, _, files in os.walk(project_copy):
                for name in files:
                    if not name.endswith(".rs"):
                        continue
                    path = os.path.join(root, name)
                    with open(path, "r", encoding="utf-8") as f:
                        source = f.read()
                    updated, count = re.subn(
                        re.escape(ORIGINAL_HASH),
                        dynamic_hash,
                        source,
                        flags=re.IGNORECASE,
                    )
                    if count:
                        with open(path, "w", encoding="utf-8") as f:
                            f.write(updated)
                        replacements += count

            assert replacements > 0, (
                "The Rust cracker source does not contain the extracted MD5 target "
                "hash, so its brute-force behavior could not be exercised."
            )

            target_dir = os.path.join(work_dir, "target")
            result = run_cracker(project_copy, target_dir)
            assert_output_contains_pin(result, pin)


def test_reported_pin_executes_vault_and_reproduces_flag():
    with open("/home/user/audit_report.txt", "r") as f:
        pin = f.read().strip().split(":", 1)[1].strip()

    with tempfile.TemporaryDirectory(prefix="vault-check-") as work_dir:
        output_path = os.path.join(work_dir, "output.txt")
        result = subprocess.run(
            ["/home/user/vuln_vault", pin, output_path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, "The reported PIN was rejected by vuln_vault."
        assert os.path.isfile(output_path), "vuln_vault did not create its output file."
        with open(output_path, "rb") as generated, open("/home/user/flag.txt", "rb") as submitted:
            assert generated.read() == submitted.read(), (
                "flag.txt does not match the data produced by vuln_vault for the reported PIN."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
