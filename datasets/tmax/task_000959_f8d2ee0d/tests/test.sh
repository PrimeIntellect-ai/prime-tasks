#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_auditor.py
import ast
import hashlib
import json
import os
import secrets
import stat
import subprocess
import tempfile

AUDITOR = "/home/user/auditor.py"
REPORT = "/home/user/audit_report.json"
TARGET = "/home/user/audit_target"
LOGIN = os.path.join(TARGET, "login.py")
CHECKSUM = os.path.join(TARGET, "checksum.sha256")
CERT = os.path.join(TARGET, "server.crt")
EXPECTED_KEYS = {"world_writable", "checksum_match", "cert_expired", "open_redirect_param"}


def run_auditor():
    if os.path.lexists(REPORT):
        os.unlink(REPORT)
    result = subprocess.run(
        ["python3", AUDITOR],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"auditor.py exited with {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT), f"The report {REPORT} does not exist."
    with open(REPORT, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"The file {REPORT} does not contain valid JSON: {exc}")
    assert set(report.keys()) == EXPECTED_KEYS, (
        f"The JSON report keys do not match the expected keys. Found: {list(report.keys())}"
    )
    assert type(report["world_writable"]) is bool
    assert type(report["checksum_match"]) is bool
    assert type(report["cert_expired"]) is bool
    assert type(report["open_redirect_param"]) is str
    return report


def derive_redirect_parameter(path):
    with open(path, "r") as f:
        tree = ast.parse(f.read(), filename=path)

    tainted_names = {}
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign) or len(node.targets) != 1:
            continue
        target = node.targets[0]
        value = node.value
        if not isinstance(target, ast.Name) or not isinstance(value, ast.Call):
            continue
        func = value.func
        if not (
            isinstance(func, ast.Attribute)
            and func.attr == "get"
            and isinstance(func.value, ast.Attribute)
            and func.value.attr == "args"
            and isinstance(func.value.value, ast.Name)
            and func.value.value.id == "request"
            and value.args
            and isinstance(value.args[0], ast.Constant)
            and isinstance(value.args[0].value, str)
        ):
            continue
        tainted_names[target.id] = value.args[0].value

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not node.args:
            continue
        if isinstance(node.func, ast.Name) and node.func.id == "redirect":
            argument = node.args[0]
            if isinstance(argument, ast.Name) and argument.id in tainted_names:
                return tainted_names[argument.id]
    raise AssertionError("Verifier could not derive an open-redirect parameter from login.py")


def derive_expected():
    world_writable = bool(os.stat(LOGIN).st_mode & stat.S_IWOTH)

    with open(LOGIN, "rb") as f:
        actual_hash = hashlib.sha256(f.read()).hexdigest()
    with open(CHECKSUM, "r") as f:
        expected_hash = f.read().split()[0].lower()

    cert_check = subprocess.run(
        ["openssl", "x509", "-in", CERT, "-checkend", "0", "-noout"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert cert_check.returncode in (0, 1), "Unable to validate server.crt with openssl"

    return {
        "world_writable": world_writable,
        "checksum_match": actual_hash == expected_hash,
        "cert_expired": cert_check.returncode == 1,
        "open_redirect_param": derive_redirect_parameter(LOGIN),
    }


def assert_original_report(report):
    assert set(report.keys()) == EXPECTED_KEYS, (
        f"The JSON report keys do not match the expected keys. Found: {list(report.keys())}"
    )
    assert report["world_writable"] is True, "Expected 'world_writable' to be true."
    assert report["checksum_match"] is False, "Expected 'checksum_match' to be false."
    assert report["cert_expired"] is True, "Expected 'cert_expired' to be true."
    assert report["open_redirect_param"] == "return_to_path", (
        "Expected 'open_redirect_param' to be 'return_to_path'."
    )


def snapshot(path):
    with open(path, "rb") as f:
        return f.read(), stat.S_IMODE(os.stat(path).st_mode)


def restore(path, saved):
    data, mode = saved
    with open(path, "wb") as f:
        f.write(data)
    os.chmod(path, mode)


assert os.path.isfile(AUDITOR), f"The script {AUDITOR} does not exist."
assert not os.path.islink(AUDITOR), f"The script {AUDITOR} must be a regular file, not a symlink."
assert stat.S_ISREG(os.lstat(AUDITOR).st_mode), f"The script {AUDITOR} is not a regular file."
assert os.path.getsize(AUDITOR) > 0, f"The script {AUDITOR} is empty."

saved = {path: snapshot(path) for path in (LOGIN, CHECKSUM, CERT)}

try:
    # Execute the submitted artifact and retain all original report assertions.
    baseline = run_auditor()
    assert baseline == derive_expected()
    assert_original_report(baseline)

    # Exercise permission detection independently.
    for path, value in saved.items():
        restore(path, value)
    os.chmod(LOGIN, stat.S_IMODE(os.stat(LOGIN).st_mode) & ~stat.S_IWOTH)
    expected = derive_expected()
    assert expected["world_writable"] is False
    assert run_auditor() == expected

    # Exercise checksum verification independently.
    for path, value in saved.items():
        restore(path, value)
    with open(LOGIN, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    with open(CHECKSUM, "w") as f:
        f.write(f"{digest}  login.py\n")
    expected = derive_expected()
    assert expected["checksum_match"] is True
    assert run_auditor() == expected

    # Replace the expired certificate with a newly generated currently-valid one.
    for path, value in saved.items():
        restore(path, value)
    with tempfile.TemporaryDirectory() as tmp:
        key = os.path.join(tmp, "key.pem")
        subprocess.run(
            ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-keyout", key,
             "-out", CERT, "-days", "2", "-nodes", "-subj", "/CN=localhost"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        expected = derive_expected()
        assert expected["cert_expired"] is False
        assert run_auditor() == expected

    # Randomize the vulnerable request argument so a hardcoded answer cannot pass.
    for path, value in saved.items():
        restore(path, value)
    random_param = "redirect_" + secrets.token_hex(12)
    with open(LOGIN, "r") as f:
        source = f.read()
    assert source.count("return_to_path") == 1
    with open(LOGIN, "w") as f:
        f.write(source.replace("return_to_path", random_param))
    expected = derive_expected()
    assert expected["open_redirect_param"] == random_param
    assert run_auditor() == expected
finally:
    # Leave the target and required final report in their original state.
    for path, value in saved.items():
        restore(path, value)
    final_report = run_auditor()
    assert_original_report(final_report)
PY_EOF

if python3 /tmp/verify_auditor.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
