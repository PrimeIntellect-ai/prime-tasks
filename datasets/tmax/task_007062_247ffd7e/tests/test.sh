#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import shutil
import stat
import subprocess
import tempfile


def test_audit_script_exists():
    script = "/home/user/audit.py"
    assert os.path.exists(script), f"Required script {script} does not exist."
    mode = os.lstat(script).st_mode
    assert stat.S_ISREG(mode), f"{script} must be a regular file."


def test_audit_trail_json():
    audit_file = "/home/user/audit_trail.json"
    assert os.path.isfile(audit_file), f"Audit trail file {audit_file} was not created."

    with open(audit_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{audit_file} does not contain valid JSON."

    assert "malicious_ips" in data, "Missing 'malicious_ips' key in audit trail."
    assert "quarantined_files" in data, "Missing 'quarantined_files' key in audit trail."

    expected_ips = ["10.0.0.55", "172.16.0.4", "192.168.1.11"]
    expected_files = ["file_beta.bin"]

    # Check malicious IPs (deduplicated and sorted)
    assert isinstance(data["malicious_ips"], list), "'malicious_ips' must be a list."
    assert sorted(data["malicious_ips"]) == expected_ips, f"Expected malicious_ips to be {expected_ips}, got {data['malicious_ips']}"

    # Check quarantined files (deduplicated and sorted)
    assert isinstance(data["quarantined_files"], list), "'quarantined_files' must be a list."
    assert sorted(data["quarantined_files"]) == expected_files, f"Expected quarantined_files to be {expected_files}, got {data['quarantined_files']}"


def test_quarantined_file_permissions():
    quarantined_file = "/home/user/uploads/file_beta.bin"
    assert os.path.isfile(quarantined_file), f"File {quarantined_file} does not exist."

    file_stat = os.stat(quarantined_file)
    file_mode = stat.S_IMODE(file_stat.st_mode)

    assert file_mode == 0o400, f"Expected permissions for {quarantined_file} to be 0400, got {oct(file_mode).replace('0o', '0')}"


def test_clean_file_permissions_unchanged():
    # Ensure clean files were not accidentally quarantined
    clean_files = [
        "/home/user/uploads/file_alpha.txt",
        "/home/user/uploads/file_gamma.jpg"
    ]
    for clean_file in clean_files:
        if os.path.isfile(clean_file):
            file_stat = os.stat(clean_file)
            file_mode = stat.S_IMODE(file_stat.st_mode)
            assert file_mode != 0o400, f"Clean file {clean_file} should not have 0400 permissions."


def test_script_processes_fresh_inputs():
    home = "/home/user"
    logs_path = os.path.join(home, "server_logs.json")
    hashes_path = os.path.join(home, "hashes.txt")
    uploads_path = os.path.join(home, "uploads")
    report_path = os.path.join(home, "audit_trail.json")
    script_path = os.path.join(home, "audit.py")

    backup = tempfile.mkdtemp(prefix="audit-verifier-")
    shutil.copy2(logs_path, os.path.join(backup, "server_logs.json"))
    shutil.copy2(hashes_path, os.path.join(backup, "hashes.txt"))
    shutil.copytree(uploads_path, os.path.join(backup, "uploads"))
    had_report = os.path.isfile(report_path)
    if had_report:
        shutil.copy2(report_path, os.path.join(backup, "audit_trail.json"))

    try:
        shutil.rmtree(uploads_path)
        os.mkdir(uploads_path)

        actual_contents = {
            "fresh_clean_a.dat": b"fresh clean payload A",
            "fresh_bad_b.dat": b"altered payload B",
            "fresh_clean_c.dat": b"fresh clean payload C",
        }
        expected_contents = {
            "fresh_clean_a.dat": actual_contents["fresh_clean_a.dat"],
            "fresh_bad_b.dat": b"original payload B",
            "fresh_clean_c.dat": actual_contents["fresh_clean_c.dat"],
        }

        for filename, content in actual_contents.items():
            path = os.path.join(uploads_path, filename)
            with open(path, "wb") as f:
                f.write(content)
            os.chmod(path, 0o666)

        expected_hashes = {
            filename: hashlib.sha256(content).hexdigest()
            for filename, content in expected_contents.items()
        }
        with open(hashes_path, "w") as f:
            for filename in sorted(expected_hashes):
                f.write(f"{expected_hashes[filename]}  {filename}\n")

        logs = [
            {"ip": "203.0.113.9", "method": "GET", "path": "/a/../secret", "headers": {"User-Agent": "safe", "Cookie": ""}, "uploaded_file_id": "fresh_clean_a.dat"},
            {"ip": "203.0.113.2", "method": "GET", "path": "/assets/%2e%2e%2fkeys", "headers": {"User-Agent": "safe", "Cookie": ""}, "uploaded_file_id": None},
            {"ip": "203.0.113.7", "method": "GET", "path": "/search?q=' OR true", "headers": {"User-Agent": "safe", "Cookie": ""}, "uploaded_file_id": None},
            {"ip": "203.0.113.5", "method": "GET", "path": "/home", "headers": {"User-Agent": "safe", "Cookie": "id=1 UNION SELECT password"}, "uploaded_file_id": "fresh_bad_b.dat"},
            {"ip": "203.0.113.4", "method": "GET", "path": "/view?<script>alert(1)</script>", "headers": {"User-Agent": "safe", "Cookie": ""}, "uploaded_file_id": None},
            {"ip": "203.0.113.3", "method": "GET", "path": "/home", "headers": {"User-Agent": "browser <script>x</script>", "Cookie": ""}, "uploaded_file_id": "fresh_clean_c.dat"},
            {"ip": "203.0.113.9", "method": "GET", "path": "/another/../target", "headers": {"User-Agent": "safe", "Cookie": ""}, "uploaded_file_id": "fresh_clean_a.dat"},
            {"ip": "203.0.113.100", "method": "GET", "path": "/union select/<SCRIPT>", "headers": {"User-Agent": "' OR only-in-agent", "Cookie": "../ and <script> only-in-cookie"}, "uploaded_file_id": "fresh_bad_b.dat"},
        ]
        with open(logs_path, "w") as f:
            json.dump(logs, f)

        expected_ips = set()
        referenced_files = set()
        for entry in logs:
            path = entry["path"]
            headers = entry.get("headers", {})
            user_agent = headers.get("User-Agent", "")
            cookie = headers.get("Cookie", "")
            malicious = (
                "../" in path
                or "%2e%2e%2f" in path
                or "' OR " in path
                or "UNION SELECT" in path
                or "' OR " in cookie
                or "UNION SELECT" in cookie
                or "<script>" in path
                or "<script>" in user_agent
            )
            if malicious:
                expected_ips.add(entry["ip"])
            if entry.get("uploaded_file_id") is not None:
                referenced_files.add(entry["uploaded_file_id"])

        expected_quarantined = []
        for filename in referenced_files:
            with open(os.path.join(uploads_path, filename), "rb") as f:
                actual_hash = hashlib.sha256(f.read()).hexdigest()
            if actual_hash != expected_hashes[filename]:
                expected_quarantined.append(filename)

        if os.path.lexists(report_path):
            os.unlink(report_path)

        result = subprocess.run(
            ["python3", script_path],
            cwd=home,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Executing {script_path} on fresh inputs failed with exit code "
            f"{result.returncode}. stderr: {result.stderr}"
        )
        assert os.path.isfile(report_path), "The script did not create audit_trail.json on fresh inputs."

        with open(report_path, "r") as f:
            generated = json.load(f)

        assert set(generated.keys()) == {"malicious_ips", "quarantined_files"}, "Audit report has an incorrect structure."
        assert generated["malicious_ips"] == sorted(expected_ips), (
            f"Fresh-input malicious_ips mismatch: expected {sorted(expected_ips)}, "
            f"got {generated['malicious_ips']}"
        )
        assert generated["quarantined_files"] == sorted(expected_quarantined), (
            f"Fresh-input quarantined_files mismatch: expected {sorted(expected_quarantined)}, "
            f"got {generated['quarantined_files']}"
        )

        for filename in actual_contents:
            mode = stat.S_IMODE(os.stat(os.path.join(uploads_path, filename)).st_mode)
            if filename in expected_quarantined:
                assert mode == 0o400, f"Expected {filename} to be quarantined with mode 0400, got {oct(mode)}."
            else:
                assert mode == 0o666, f"Clean file {filename} had its permissions changed to {oct(mode)}."
    finally:
        shutil.copy2(os.path.join(backup, "server_logs.json"), logs_path)
        shutil.copy2(os.path.join(backup, "hashes.txt"), hashes_path)
        if os.path.exists(uploads_path):
            shutil.rmtree(uploads_path)
        shutil.copytree(os.path.join(backup, "uploads"), uploads_path)
        if had_report:
            shutil.copy2(os.path.join(backup, "audit_trail.json"), report_path)
        elif os.path.lexists(report_path):
            os.unlink(report_path)
        shutil.rmtree(backup)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
