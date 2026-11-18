#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tarfile
from pathlib import Path

BACKUP = Path("/home/user/backup/manifests_backup.tar.gz")
PROXY = Path("/home/user/proxy.conf")
MANIFESTS = Path("/home/user/manifests")
SOURCE = Path("/home/user/operator.c")
BINARY = Path("/home/user/operator")


def test_env_var_exported():
    """Keep the original profile-content assertion."""
    bashrc_path = "/home/user/.bashrc"
    profile_path = "/home/user/.profile"
    found = False
    expected_string = "OPERATOR_BACKUP_DIR=/home/user/backup"

    if os.path.exists(bashrc_path):
        with open(bashrc_path, "r") as f:
            if expected_string in f.read():
                found = True

    if not found and os.path.exists(profile_path):
        with open(profile_path, "r") as f:
            if expected_string in f.read():
                found = True

    assert found, f"Could not find '{expected_string}' in {bashrc_path} or {profile_path}"


def test_env_var_is_actually_exported():
    for profile in ("/home/user/.bashrc", "/home/user/.profile"):
        if not os.path.isfile(profile):
            continue
        result = subprocess.run(
            ["bash", "--noprofile", "--norc", "-ic",
             'source "$1" >/dev/null 2>&1; printenv OPERATOR_BACKUP_DIR',
             "bash", profile],
            text=True, capture_output=True, timeout=10,
            env={**os.environ, "HOME": "/home/user"},
        )
        if result.returncode == 0 and result.stdout.strip().splitlines()[-1:] == ["/home/user/backup"]:
            return
    raise AssertionError("OPERATOR_BACKUP_DIR is not actually exported by .bashrc or .profile")


def test_backup_exists():
    """Keep the original backup assertion."""
    backup_path = "/home/user/backup/manifests_backup.tar.gz"
    assert os.path.isfile(backup_path), f"Backup archive not found at {backup_path}"


def test_proxy_conf_weights():
    """Keep the original proxy weight assertions."""
    proxy_conf_path = "/home/user/proxy.conf"
    assert os.path.isfile(proxy_conf_path), f"Proxy configuration not found at {proxy_conf_path}"

    with open(proxy_conf_path, "r") as f:
        content = f.read()

    v1_match = re.search(r'8081.*weight[= ]?(\d+)', content)
    v2_match = re.search(r'8082.*weight[= ]?(\d+)', content)

    assert v1_match is not None, "Could not find weight for port 8081 (service-v1) in proxy.conf"
    assert v2_match is not None, "Could not find weight for port 8082 (service-v2) in proxy.conf"

    w1 = float(v1_match.group(1))
    w2 = float(v2_match.group(1))
    assert (w1 + w2) > 0, "Sum of weights must be greater than 0"

    p1 = w1 / (w1 + w2)
    target_p1 = 0.75
    mse = (p1 - target_p1) ** 2
    threshold = 0.001
    assert mse <= threshold, f"Weight ratio MSE {mse} exceeds threshold {threshold}. Extracted ratio for v1: {p1:.3f}, expected: {target_p1}"


def diagram_weights():
    result = subprocess.run(
        ["tesseract", "/app/diagram.png", "stdout"],
        text=True, capture_output=True, timeout=20, check=True,
    )
    text = result.stdout
    v1 = re.search(r"service-v1\s*:\s*(\d+)\s*%", text, re.IGNORECASE)
    v2 = re.search(r"service-v2\s*:\s*(\d+)\s*%", text, re.IGNORECASE)
    assert v1 and v2, f"Could not derive service weights from diagram OCR: {text!r}"
    return int(v1.group(1)), int(v2.group(1))


def proxy_weight_pair(content):
    content = re.sub(r"#.*", "", content)

    # Nginx: both weighted server directives must occur in one upstream block.
    for match in re.finditer(r"\bupstream\s+[^\s{]+\s*\{([^{}]*)\}", content, re.I | re.S):
        block = match.group(1)
        one = re.search(r"\bserver\s+127\.0\.0\.1:8081\b[^;]*\bweight\s*=\s*(\d+)\s*;", block, re.I)
        two = re.search(r"\bserver\s+127\.0\.0\.1:8082\b[^;]*\bweight\s*=\s*(\d+)\s*;", block, re.I)
        if one and two:
            return int(one.group(1)), int(two.group(1))

    # HAProxy: both weighted server directives must occur in one backend section.
    section_re = re.compile(
        r"(?ms)^\s*backend\s+\S+\s*$([\s\S]*?)(?=^\s*(?:backend|frontend|listen|defaults|global)\b|\Z)",
        re.I,
    )
    for match in section_re.finditer(content):
        block = match.group(1)
        one = re.search(r"(?m)^\s*server\s+\S+\s+127\.0\.0\.1:8081\b[^\n#]*\bweight\s+(\d+)\b", block, re.I)
        two = re.search(r"(?m)^\s*server\s+\S+\s+127\.0\.0\.1:8082\b[^\n#]*\bweight\s+(\d+)\b", block, re.I)
        if one and two:
            return int(one.group(1)), int(two.group(1))

    raise AssertionError("proxy.conf does not contain a structurally valid Nginx upstream or HAProxy backend with both services")


def archive_contents():
    assert BACKUP.is_file() and not BACKUP.is_symlink(), "Backup was not generated as a regular file"
    result = {}
    with tarfile.open(BACKUP, "r:gz") as archive:
        for member in archive.getmembers():
            parts = [part for part in Path(member.name).parts if part not in ("/", ".")]
            assert ".." not in parts, f"Unsafe archive member: {member.name}"
            if "manifests" not in parts or not member.isfile():
                continue
            index = parts.index("manifests")
            relative = "/".join(parts[index + 1:])
            if not relative:
                continue
            extracted = archive.extractfile(member)
            assert extracted is not None
            assert relative not in result, f"Duplicate manifest in archive: {relative}"
            result[relative] = extracted.read()
    return result


def current_manifest_contents():
    return {
        str(path.relative_to(MANIFESTS)): path.read_bytes()
        for path in MANIFESTS.rglob("*") if path.is_file()
    }


def run_and_validate(binary):
    marker = MANIFESTS / ("audit_" + secrets.token_hex(8) + ".json")
    marker.write_text('{"audit_nonce":"' + secrets.token_hex(24) + '"}\n')
    expected = current_manifest_contents()
    try:
        BACKUP.unlink(missing_ok=True)
        PROXY.unlink(missing_ok=True)
        env = dict(os.environ)
        env["OPERATOR_BACKUP_DIR"] = "/home/user/backup"
        result = subprocess.run(
            [str(binary)], cwd="/home/user", env=env,
            text=True, capture_output=True, timeout=30,
        )
        assert result.returncode == 0, f"{binary} failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
        assert archive_contents() == expected, "Fresh backup does not exactly contain the manifests present at execution time"
        assert PROXY.is_file() and not PROXY.is_symlink(), "Operator did not freshly generate proxy.conf"
        actual_v1, actual_v2 = proxy_weight_pair(PROXY.read_text())
        target_v1, target_v2 = diagram_weights()
        assert actual_v1 > 0 and actual_v2 > 0, "Proxy weights must be positive"
        assert actual_v1 * target_v2 == actual_v2 * target_v1, (
            f"Proxy ratio {actual_v1}:{actual_v2} is not the exact diagram ratio {target_v1}:{target_v2}"
        )
    finally:
        marker.unlink(missing_ok=True)


def test_operator_source_binary_and_runtime_behavior(tmp_path):
    assert SOURCE.is_file() and not SOURCE.is_symlink(), "operator.c is missing or is not a regular source file"
    assert SOURCE.stat().st_size > 0, "operator.c is empty"
    assert BINARY.is_file() and not BINARY.is_symlink(), "Compiled /home/user/operator is missing"
    assert os.access(BINARY, os.X_OK), "/home/user/operator is not executable"
    with BINARY.open("rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/operator is not a compiled ELF program"

    # Exercise the submitted executable on a nonce manifest.
    run_and_validate(BINARY)

    # Recompile the submitted C source and exercise that result too, tying the
    # required source file to the implemented behavior.
    rebuilt = tmp_path / "operator_rebuilt"
    compile_result = subprocess.run(
        ["gcc", str(SOURCE), "-o", str(rebuilt)],
        text=True, capture_output=True, timeout=30,
    )
    assert compile_result.returncode == 0, f"operator.c does not compile: {compile_result.stderr}"
    run_and_validate(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
