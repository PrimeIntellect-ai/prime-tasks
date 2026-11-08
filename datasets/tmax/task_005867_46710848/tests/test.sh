#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shlex
import shutil
import sqlite3
import subprocess
import tarfile
import tempfile

WAF_DIR = "/home/user/waf_project"
EXPECTED_LOG_LINES = None
RELEASE_FILE_BYTES = None


def test_verify_sigs_sh_exists_and_executable():
    script_path = os.path.join(WAF_DIR, "verify_sigs.sh")
    assert os.path.isfile(script_path), f"Bash script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        first_line = f.readline().strip()
    assert "bash" in first_line or "sh" in first_line, f"Script {script_path} does not appear to be a Bash/shell script."


def test_verify_sigs_sh_behavior_on_varied_inputs():
    script_path = os.path.join(WAF_DIR, "verify_sigs.sh")
    tag = secrets.token_hex(6)

    with tempfile.TemporaryDirectory() as tmp:
        target = os.path.join(tmp, "targets")
        os.mkdir(target)

        good_name = f"valid_{tag}.rule"
        bad_name = f"changed_{tag}.conf"
        missing_name = f"missing_{tag}.dat"
        good_data = secrets.token_bytes(97)
        bad_data = secrets.token_bytes(113)

        with open(os.path.join(target, good_name), "wb") as f:
            f.write(good_data)
        with open(os.path.join(target, bad_name), "wb") as f:
            f.write(bad_data)

        sig_path = os.path.join(tmp, "varied_signatures.txt")
        with open(sig_path, "w") as f:
            f.write(f"{good_name}:{hashlib.sha256(good_data).hexdigest()}\n")
            f.write("\n")
            f.write(f"{bad_name}:{'0' * 64}\n")
            f.write(f"{missing_name}:{hashlib.sha256(b'not present').hexdigest()}\n")

        result = subprocess.run(
            [script_path, sig_path, target],
            capture_output=True,
            text=True,
            timeout=20,
        )

        assert result.stdout.splitlines() == [
            f"OK: {good_name}",
            f"FAIL: {bad_name}",
            f"FAIL: {missing_name}",
        ], f"verify_sigs.sh produced incorrect output:\n{result.stdout}\nstderr:\n{result.stderr}"


def test_database_schema_migrated():
    db_path = os.path.join(WAF_DIR, "db", "rules.sqlite")
    assert os.path.isfile(db_path), f"Database file {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(core_rules);")
    columns = cursor.fetchall()

    severity_col = None
    for col in columns:
        if col[1] == "severity":
            severity_col = col
            break

    assert severity_col is not None, "Column 'severity' is missing from 'core_rules' table."
    assert "INT" in severity_col[2].upper(), "Column 'severity' is not of type INTEGER."
    assert str(severity_col[4]) == "5", f"Column 'severity' does not have default value 5. Found: {severity_col[4]}"
    conn.close()


def test_make_release_target():
    global EXPECTED_LOG_LINES, RELEASE_FILE_BYTES

    script_path = os.path.join(WAF_DIR, "verify_sigs.sh")
    backup_path = os.path.join("/tmp", f"submitted_verify_sigs_{secrets.token_hex(8)}.sh")
    marker_path = os.path.join("/tmp", f"verify_invoked_{secrets.token_hex(8)}")
    marker_token = secrets.token_hex(16)
    tag = secrets.token_hex(6)

    shutil.copy2(script_path, backup_path)

    # Clean first to ensure the target actually builds the artifacts.
    subprocess.run(["make", "clean"], cwd=WAF_DIR, capture_output=True)
    assert os.path.isfile(script_path), "'make clean' removed verify_sigs.sh."

    controlled = {
        "rule1.conf": secrets.token_bytes(81),
        "rule2.conf": secrets.token_bytes(129),
        f"extra_{tag}.conf": secrets.token_bytes(173),
    }
    downloads = os.path.join(WAF_DIR, "downloads")
    for name, data in controlled.items():
        with open(os.path.join(downloads, name), "wb") as f:
            f.write(data)

    sig_path = os.path.join(WAF_DIR, "signatures.txt")
    with open(sig_path, "w") as f:
        for name, data in controlled.items():
            f.write(f"{name}:{hashlib.sha256(data).hexdigest()}\n")

    # The wrapper calls the submitted implementation, while also proving that
    # release invoked ./verify_sigs.sh with the required arguments. It creates
    # one signed file during verification so the archive must be made afterward.
    order_name = f"created_during_verify_{tag}.conf"
    order_text = f"order-probe-{marker_token}\n"
    order_hash = hashlib.sha256(order_text.encode()).hexdigest()
    wrapper = f'''#!/bin/bash
if [ "$#" -eq 2 ] && [ "$1" = "signatures.txt" ] && [ "$2" = "downloads/" ]; then
    printf '%s' {shlex.quote(marker_token)} > {shlex.quote(marker_path)}
    printf '%s' {shlex.quote(order_text)} > {shlex.quote(os.path.join(downloads, order_name))}
    printf '%s:%s\\n' {shlex.quote(order_name)} {shlex.quote(order_hash)} >> {shlex.quote(sig_path)}
fi
exec {shlex.quote(backup_path)} "$@"
'''
    with open(script_path, "w") as f:
        f.write(wrapper)
    os.chmod(script_path, 0o755)

    try:
        result = subprocess.run(
            ["make", "release"],
            cwd=WAF_DIR,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"'make release' failed with error:\n{result.stderr}"
        assert os.path.isfile(marker_path), "The release target did not execute ./verify_sigs.sh."
        with open(marker_path) as f:
            assert f.read() == marker_token, "The verification invocation marker was invalid."
    finally:
        shutil.copy2(backup_path, script_path)
        os.chmod(script_path, 0o755)
        if os.path.exists(backup_path):
            os.remove(backup_path)
        if os.path.exists(marker_path):
            os.remove(marker_path)

    EXPECTED_LOG_LINES = [f"OK: {name}" for name in controlled]
    EXPECTED_LOG_LINES.append(f"OK: {order_name}")

    RELEASE_FILE_BYTES = {}
    db_path = os.path.join(WAF_DIR, "db", "rules.sqlite")
    with open(db_path, "rb") as f:
        RELEASE_FILE_BYTES["db/rules.sqlite"] = f.read()
    for root, _, files in os.walk(downloads):
        for filename in files:
            full_path = os.path.join(root, filename)
            relative = os.path.relpath(full_path, WAF_DIR).replace(os.sep, "/")
            with open(full_path, "rb") as f:
                RELEASE_FILE_BYTES[relative] = f.read()


def test_build_logs_content():
    log_path = os.path.join(WAF_DIR, "build_logs.txt")
    assert os.path.isfile(log_path), f"Log file {log_path} was not created."

    with open(log_path, "r") as f:
        content = f.read()

    assert "OK: rule1.conf" in content, "build_logs.txt is missing 'OK: rule1.conf'"
    assert "OK: rule2.conf" in content, "build_logs.txt is missing 'OK: rule2.conf'"
    assert "FAIL" not in content, "build_logs.txt contains unexpected FAIL messages."
    assert content.splitlines() == EXPECTED_LOG_LINES, f"build_logs.txt was not the exact verifier output: {content!r}"


def test_tarball_contents():
    tar_path = os.path.join(WAF_DIR, "waf_release.tar.gz")
    assert os.path.isfile(tar_path), f"Tarball {tar_path} was not created."

    with tarfile.open(tar_path, "r:gz") as tar:
        members = tar.getnames()

        def contains_path(expected):
            return any(m.endswith(expected) for m in members)

        assert contains_path("db/rules.sqlite"), "Tarball is missing db/rules.sqlite"
        assert contains_path("downloads/rule1.conf"), "Tarball is missing downloads/rule1.conf"
        assert contains_path("downloads/rule2.conf"), "Tarball is missing downloads/rule2.conf"

        for expected_path, expected_data in RELEASE_FILE_BYTES.items():
            matches = [m for m in tar.getmembers() if m.name.endswith(expected_path) and m.isfile()]
            assert matches, f"Tarball is missing {expected_path}"
            archived = tar.extractfile(matches[0])
            assert archived is not None
            assert archived.read() == expected_data, f"Archived content differs for {expected_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
