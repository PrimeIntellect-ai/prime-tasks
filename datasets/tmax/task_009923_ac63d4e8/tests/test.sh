#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import os
import shutil
import stat
import subprocess
import tempfile
import uuid

AUDIT_RESULTS_FILE = "/home/user/audit_results.csv"
WEBAPP_DIR = "/home/user/webapp"
EXPECTED_HEADER = ["Filename", "Vulnerability", "Current_SHA256"]


def compute_sha256(path):
    hasher = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def read_known_hashes():
    hashes = {}
    with open(os.path.join(WEBAPP_DIR, "checksums.txt"), "r", encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split(None, 1)
            if len(parts) == 2:
                name = parts[1].strip()
                if name.startswith("*"):
                    name = name[1:]
                hashes[name] = parts[0].lower()
    return hashes


def derive_expected_rows():
    known = read_known_hashes()
    rows = []
    for root, _, files in os.walk(WEBAPP_DIR):
        for filename in files:
            path = os.path.join(root, filename)
            if not stat.S_ISREG(os.stat(path).st_mode):
                continue
            if not (os.stat(path).st_mode & stat.S_IWOTH):
                continue

            relname = os.path.relpath(path, WEBAPP_DIR)
            original_hash = known.get(relname)
            if original_hash is None:
                original_hash = known.get(filename)
            if original_hash is None:
                continue

            current_hash = compute_sha256(path)
            if current_hash.lower() == original_hash:
                continue

            with open(path, "rb") as f:
                content = f.read()
            vulnerability = None
            if b"eval(" in content or b"innerHTML =" in content:
                vulnerability = "XSS"
            elif b"Content-Security-Policy" in content and b"'unsafe-inline'" in content:
                vulnerability = "CSP"

            if vulnerability is not None:
                rows.append([os.path.basename(path), vulnerability, current_hash])

    rows.sort(key=lambda row: row[0])
    return rows


def read_and_validate_report():
    assert os.path.isfile(AUDIT_RESULTS_FILE), (
        f"The audit report {AUDIT_RESULTS_FILE} does not exist."
    )
    with open(AUDIT_RESULTS_FILE, "r", newline="") as f:
        rows = list(csv.reader(f))
    assert rows, f"The file {AUDIT_RESULTS_FILE} is empty."
    assert rows[0] == EXPECTED_HEADER, (
        f"Header is incorrect. Expected {EXPECTED_HEADER}, got {rows[0]}."
    )
    data_rows = rows[1:]
    assert all(len(row) == 3 for row in data_rows), "Every CSV data row must have exactly three fields."
    filenames = [row[0] for row in data_rows]
    assert filenames == sorted(filenames), (
        "The CSV data rows are not sorted alphabetically by Filename."
    )
    expected = derive_expected_rows()
    assert data_rows == expected, f"Expected rows {expected}, got {data_rows}."


def candidate_commands(path):
    commands = []
    try:
        with open(path, "rb") as f:
            first = f.readline(512)
    except OSError:
        return commands

    lower = path.lower()
    if lower.endswith(".py"):
        commands.append(["python3", path])
    elif lower.endswith((".sh", ".bash")):
        commands.append(["bash", path])
    elif first.startswith(b"#!"):
        if b"python" in first:
            commands.append(["python3", path])
        elif b"bash" in first or b"/sh" in first:
            commands.append(["bash", path])
        elif os.access(path, os.X_OK):
            commands.append([path])
    elif os.access(path, os.X_OK):
        commands.append([path])
    elif "audit" in os.path.basename(path).lower():
        commands.extend((["python3", path], ["bash", path]))
    return commands


def find_candidate_commands():
    found = []
    excluded = {
        os.path.realpath(AUDIT_RESULTS_FILE),
        os.path.realpath("/tmp/test_final_state.py"),
    }
    for base in ("/home/user", "/tmp"):
        for root, dirs, files in os.walk(base):
            dirs[:] = [d for d in dirs if d not in {"__pycache__", ".pytest_cache"}]
            for name in files:
                path = os.path.join(root, name)
                real = os.path.realpath(path)
                if real in excluded:
                    continue
                try:
                    if not os.path.isfile(path) or os.path.getsize(path) > 2_000_000:
                        continue
                except OSError:
                    continue
                for command in candidate_commands(path):
                    found.append((path, command))
    found.sort(key=lambda item: ("audit" not in os.path.basename(item[0]).lower(), item[0]))
    return found


def add_challenge_files():
    token = uuid.uuid4().hex[:12]
    cases = [
        (f"{token}_alpha.html", b"<script>eval(location.hash)</script>\n", 0o666, "0" * 64),
        (f"{token}_bravo.html", b"Content-Security-Policy: script-src 'unsafe-inline'\n", 0o666, "1" * 64),
        (f"{token}_charlie.txt", b"ordinary changed content\n", 0o666, "2" * 64),
        (f"{token}_private.js", b"eval(untrusted)\n", 0o644, "3" * 64),
    ]
    checksum_lines = []
    for name, content, mode, original_hash in cases:
        path = os.path.join(WEBAPP_DIR, name)
        with open(path, "wb") as f:
            f.write(content)
        os.chmod(path, mode)
        checksum_lines.append(f"{original_hash}  {name}\n")

    matching_name = f"{token}_matching.js"
    matching_path = os.path.join(WEBAPP_DIR, matching_name)
    matching_content = b"eval(data)\n"
    with open(matching_path, "wb") as f:
        f.write(matching_content)
    os.chmod(matching_path, 0o666)
    checksum_lines.append(f"{hashlib.sha256(matching_content).hexdigest()}  {matching_name}\n")

    with open(os.path.join(WEBAPP_DIR, "checksums.txt"), "a", encoding="utf-8") as f:
        f.writelines(checksum_lines)


def test_final_state_and_audit_script():
    # Preserve the original verifier's report checks, but derive every qualifying
    # row from permissions, checksums, and contents rather than fixed filenames.
    read_and_validate_report()

    commands = find_candidate_commands()
    assert commands, "No audit script was found under /home/user or /tmp."

    backup_parent = tempfile.mkdtemp(prefix="audit-verifier-")
    backup = os.path.join(backup_parent, "webapp")
    shutil.copytree(WEBAPP_DIR, backup, copy_function=shutil.copy2)
    passed = False
    errors = []
    try:
        for path, command in commands:
            if os.path.exists(WEBAPP_DIR):
                shutil.rmtree(WEBAPP_DIR)
            shutil.copytree(backup, WEBAPP_DIR, copy_function=shutil.copy2)
            add_challenge_files()
            try:
                os.remove(AUDIT_RESULTS_FILE)
            except FileNotFoundError:
                pass
            try:
                subprocess.run(
                    command,
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=10,
                    check=False,
                )
                read_and_validate_report()
                passed = True
                break
            except Exception as exc:
                errors.append(f"{path}: {exc}")
    finally:
        if os.path.exists(WEBAPP_DIR):
            shutil.rmtree(WEBAPP_DIR)
        shutil.copytree(backup, WEBAPP_DIR, copy_function=shutil.copy2)
        shutil.rmtree(backup_parent, ignore_errors=True)

    assert passed, "No submitted audit script produced a correct report for dynamically generated inputs. " + "; ".join(errors[-5:])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
