#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pwd
import shutil
import stat
import subprocess
import tarfile
import tempfile
import uuid

import pytest

HOME = "/home/user"
SCRIPT = f"{HOME}/deploy.sh"
SOURCE = f"{HOME}/src/analyzer.c"
BINARY = f"{HOME}/analyzer"
BACKUP = f"{HOME}/billing_backup.tar.gz"
REPORT = f"{HOME}/cost_report.txt"
RAW = f"{HOME}/raw_billing"


def _run_as_user(argv, env=None, timeout=30):
    account = pwd.getpwnam("user")
    child_env = os.environ.copy()
    child_env["HOME"] = account.pw_dir
    child_env["USER"] = account.pw_name
    child_env["LOGNAME"] = account.pw_name
    if env:
        child_env.update(env)

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.run(
        argv,
        capture_output=True,
        env=child_env,
        preexec_fn=demote,
        timeout=timeout,
    )


def _expected_output(region):
    return (
        f"Cost analysis for region: {region}\n"
        "Idle resources found: 1\n"
        "Potential savings: $45.00\n"
    ).encode()


def _raw_files():
    result = {}
    for root, dirs, files in os.walk(RAW):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(root, name)
            assert os.path.isfile(path) and not os.path.islink(path), (
                f"Raw billing entry is not a regular file: {path}"
            )
            relative = os.path.relpath(path, RAW).replace(os.sep, "/")
            with open(path, "rb") as handle:
                result[relative] = handle.read()
    return result


def _validate_archive(path):
    assert os.path.isfile(path), f"Backup archive {path} is missing."
    with open(path, "rb") as handle:
        assert handle.read(2) == b"\x1f\x8b", "Backup is not gzip-compressed."

    archived = {}
    with tarfile.open(path, mode="r:gz") as archive:
        for member in archive.getmembers():
            normalized = member.name.replace("\\", "/")
            while normalized.startswith("./"):
                normalized = normalized[2:]
            assert not normalized.startswith("/"), "Archive contains an absolute path."
            assert ".." not in normalized.split("/"), "Archive contains path traversal."
            if member.isfile():
                extracted = archive.extractfile(member)
                assert extracted is not None
                archived[normalized] = extracted.read()

    expected = _raw_files()
    possible_prefixes = ("", "raw_billing", "home/user/raw_billing")
    for prefix in possible_prefixes:
        mapped = {}
        prefix_with_slash = prefix + "/" if prefix else ""
        valid = True
        for name, data in archived.items():
            if prefix and not name.startswith(prefix_with_slash):
                valid = False
                break
            relative = name[len(prefix_with_slash):] if prefix else name
            mapped[relative] = data
        if valid and mapped == expected:
            return
    raise AssertionError("Backup archive does not contain an exact copy of raw_billing.")


def _assert_analyzer_behavior(path):
    assert os.path.isfile(path), f"Compiled binary {path} is missing."
    assert os.stat(path).st_mode & stat.S_IXUSR, f"Binary {path} is not executable."
    with open(path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "Analyzer is not a compiled ELF executable."

    region = "audit-" + uuid.uuid4().hex
    result = subprocess.run(
        [path],
        capture_output=True,
        env={**os.environ, "CLOUD_REGION": region},
        timeout=10,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert result.stdout == _expected_output(region)
    assert result.stderr == b""

    unset_env = os.environ.copy()
    unset_env.pop("CLOUD_REGION", None)
    result = subprocess.run([path], capture_output=True, env=unset_env, timeout=10)
    assert result.returncode == 1
    assert result.stdout == b"Error: CLOUD_REGION not set\n"


def _assert_report_matches_binary():
    assert os.path.isfile(REPORT), f"Cost report {REPORT} is missing."
    result = subprocess.run(
        [BINARY],
        capture_output=True,
        env={**os.environ, "CLOUD_REGION": "us-east-1"},
        timeout=10,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    with open(REPORT, "rb") as handle:
        report = handle.read()
    assert report == result.stdout, "cost_report.txt does not exactly match analyzer output."
    assert report == _expected_output("us-east-1")


def test_deploy_script_exists_and_executable():
    script_path = "/home/user/deploy.sh"
    assert os.path.isfile(script_path), f"Deployment script {script_path} is missing."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Deployment script {script_path} is not executable."


def test_analyzer_compiled():
    binary_path = "/home/user/analyzer"
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} is missing."
    st = os.stat(binary_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Binary {binary_path} is not executable."


def test_backup_archive_exists():
    backup_path = "/home/user/billing_backup.tar.gz"
    assert os.path.isfile(backup_path), f"Backup archive {backup_path} is missing."


def test_cost_report_output():
    report_path = "/home/user/cost_report.txt"
    assert os.path.isfile(report_path), f"Cost report {report_path} is missing."
    with open(report_path, "r") as f:
        content = f.read().strip()
    expected_lines = [
        "Cost analysis for region: us-east-1",
        "Idle resources found: 1",
        "Potential savings: $45.00",
    ]
    for line in expected_lines:
        assert line in content, f"Expected line '{line}' not found in cost_report.txt"


def test_deploy_script_idempotent():
    result = subprocess.run([SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Running {SCRIPT} again failed with exit code {result.returncode}. "
        f"Output: {result.stderr}"
    )


def test_c_program_fixed():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "getenv" in content, "The typo 'getnv' was not fixed to 'getenv'."
    assert "stdlib.h" in content, "The missing include '<stdlib.h>' was not added."


def test_zz_real_deployment_behavior():
    # Validate the submitted source independently rather than trusting comments.
    with tempfile.TemporaryDirectory() as temporary:
        independently_built = os.path.join(temporary, "analyzer")
        compile_result = subprocess.run(
            ["gcc", SOURCE, "-o", independently_built],
            capture_output=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, compile_result.stderr.decode(errors="replace")
        _assert_analyzer_behavior(independently_built)

        # An existing backup must itself be a real archive of the billing directory.
        _validate_archive(BACKUP)

        # Remove all generated artifacts and require deploy.sh to recreate them as user.
        saved = os.path.join(temporary, "saved")
        os.mkdir(saved)
        for path in (BINARY, REPORT, BACKUP):
            shutil.move(path, os.path.join(saved, os.path.basename(path)))

        result = _run_as_user([SCRIPT])
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        _validate_archive(BACKUP)
        _assert_analyzer_behavior(BINARY)
        _assert_report_matches_binary()

        backup_stat = os.stat(BACKUP)
        with open(BACKUP, "rb") as handle:
            backup_hash = hashlib.sha256(handle.read()).digest()

        # Replace the source with a randomized valid program. A real deployment must
        # compile this current source and execute the resulting binary for the report.
        with open(SOURCE, "rb") as handle:
            original_source = handle.read()
        original_mode = stat.S_IMODE(os.stat(SOURCE).st_mode)
        nonce = "compile-probe-" + uuid.uuid4().hex
        probe = (
            "#include <stdio.h>\n"
            "int main(void) { puts(\"" + nonce + "\"); return 0; }\n"
        ).encode()
        sentinel = os.path.join(RAW, "verifier-idempotency-probe.txt")

        try:
            with open(SOURCE, "wb") as handle:
                handle.write(probe)
            os.chmod(SOURCE, original_mode)
            with open(sentinel, "wb") as handle:
                handle.write(os.urandom(32))

            result = _run_as_user([SCRIPT])
            assert result.returncode == 0, result.stderr.decode(errors="replace")
            with open(BINARY, "rb") as handle:
                assert handle.read(4) == b"\x7fELF"
            probe_run = subprocess.run([BINARY], capture_output=True, timeout=10)
            assert probe_run.returncode == 0
            assert probe_run.stdout == (nonce + "\n").encode()
            with open(REPORT, "rb") as handle:
                assert handle.read() == (nonce + "\n").encode()

            current_stat = os.stat(BACKUP)
            with open(BACKUP, "rb") as handle:
                current_hash = hashlib.sha256(handle.read()).digest()
            assert current_hash == backup_hash, "Existing backup was overwritten."
            assert current_stat.st_ino == backup_stat.st_ino, "Existing backup was replaced."
            assert current_stat.st_mtime_ns == backup_stat.st_mtime_ns, (
                "Existing backup was modified on a repeated deployment."
            )
        finally:
            with open(SOURCE, "wb") as handle:
                handle.write(original_source)
            os.chmod(SOURCE, original_mode)
            if os.path.exists(sentinel):
                os.unlink(sentinel)

        # Restore the requested final deployment from the original fixed source.
        result = _run_as_user([SCRIPT])
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        _assert_analyzer_behavior(BINARY)
        _assert_report_matches_binary()
        with open(BACKUP, "rb") as handle:
            assert hashlib.sha256(handle.read()).digest() == backup_hash
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
