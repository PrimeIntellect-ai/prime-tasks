#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_skipped_logs_file():
    skipped_file = "/home/user/skipped_logs.txt"
    assert os.path.isfile(skipped_file), f"File {skipped_file} does not exist."

    with open(skipped_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_skipped = {
        "/home/user/log_spool/app1/active.txt",
        "/home/user/log_spool/app2/serviceB/active.json"
    }

    assert set(lines) == expected_skipped, f"Expected {expected_skipped} in skipped_logs.txt, got {set(lines)}"
    assert len(lines) == len(expected_skipped), "skipped_logs.txt contains duplicates or extra lines."

def test_archive_jsonl_file():
    archive_file = "/home/user/archive.jsonl"
    assert os.path.isfile(archive_file), f"File {archive_file} does not exist."

    with open(archive_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected 4 lines in archive.jsonl, got {len(lines)}"

    expected_files = {
        "/home/user/log_spool/app1/serviceA/log1.txt",
        "/home/user/log_spool/app1/serviceA/data.csv",
        "/home/user/log_spool/app2/serviceB/event.json",
        "/home/user/log_spool/system.txt"
    }

    found_files = set()
    for line in lines:
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            assert False, f"Line in archive.jsonl is not valid JSON: {line}"

        assert "file" in data, "JSON object missing 'file' key."
        assert "content" in data, "JSON object missing 'content' key."

        found_files.add(data["file"])

        content = data["content"]
        assert ".com" not in content, f"Unredacted '.com' email found in content for {data['file']}"

        if data["file"] != "/home/user/log_spool/system.txt":
            assert "[REDACTED]" in content, f"Expected '[REDACTED]' in content for {data['file']}, but not found."

    assert found_files == expected_files, f"Expected archived files {expected_files}, got {found_files}"
TEST_EOF

ok=1
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0

if [ "$ok" -eq 1 ]; then
python3 << 'DYNAMIC_EOF' || ok=0
import fcntl
import json
import os
import re
import secrets
import subprocess
import sys

script = "/home/user/archive_logs.py"
assert os.path.isfile(script), f"Required script {script} does not exist or is not a regular file"

spool = "/home/user/log_spool"
token = secrets.token_hex(12)
dynamic_dir = os.path.join(spool, "verifier_" + token, "deep", "nested")
os.makedirs(dynamic_dir)

created = {
    os.path.join(dynamic_dir, "dynamic.txt"):
        f"marker={token}\nContact first.last+tag@sub-domain.example.com now.\n",
    os.path.join(dynamic_dir, "dynamic.csv"):
        f"id,email,marker\n7,admin.123@test-domain.com,{token}\n",
    os.path.join(dynamic_dir, "dynamic.json"):
        json.dumps({"marker": token, "user": "person_42@company.com"}) + "\n",
    os.path.join(dynamic_dir, "plain.txt"):
        f"No email is present here; unique marker {token}.\n",
    os.path.join(dynamic_dir, "shared.txt"):
        f"Shared reader {token}: compatible@shared-domain.com\n",
    os.path.join(dynamic_dir, "exclusive.json"):
        f'{{"marker":"{token}","email":"must-not-read@locked.com"}}\n',
}
for path, content in created.items():
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
with open(os.path.join(dynamic_dir, "ignored.log"), "w", encoding="utf-8") as f:
    f.write(f"{token} ignored@outside.com\n")

fixed_locked = [
    "/home/user/log_spool/app1/active.txt",
    "/home/user/log_spool/app2/serviceB/active.json",
]
held = []
# Ensure the two original active files remain exclusively locked even if the
# image's background locker was stopped after the first set of assertions.
for path in fixed_locked:
    fd = open(path, "a+")
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        pass
    held.append(fd)

exclusive_path = os.path.join(dynamic_dir, "exclusive.json")
exclusive_fd = open(exclusive_path, "r+")
fcntl.flock(exclusive_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
held.append(exclusive_fd)

shared_path = os.path.join(dynamic_dir, "shared.txt")
shared_fd = open(shared_path, "r")
fcntl.flock(shared_fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
held.append(shared_fd)

archive = "/home/user/archive.jsonl"
skipped = "/home/user/skipped_logs.txt"
for output in (archive, skipped):
    try:
        os.unlink(output)
    except FileNotFoundError:
        pass

trace = "/tmp/flock_trace_" + token + ".json"
runner = "/tmp/run_archive_" + token + ".py"
with open(runner, "w", encoding="utf-8") as f:
    f.write(r'''import fcntl
import json
import os
import runpy
import sys

real_flock = fcntl.flock
calls = []
def tracked_flock(fd, operation, *args):
    try:
        number = fd if isinstance(fd, int) else fd.fileno()
        path = os.path.realpath(os.readlink(f"/proc/self/fd/{number}"))
    except Exception:
        path = None
    calls.append({"path": path, "operation": int(operation)})
    return real_flock(fd, operation, *args)

fcntl.flock = tracked_flock
try:
    runpy.run_path(sys.argv[1], run_name="__main__")
finally:
    with open(os.environ["TRACE_PATH"], "w", encoding="utf-8") as out:
        json.dump(calls, out)
''')
os.chmod(runner, 0o644)

result = subprocess.run(
    ["runuser", "-u", "user", "--", "env", f"TRACE_PATH={trace}",
     sys.executable, runner, script],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=15,
)
assert result.returncode == 0, (
    f"Executing {script} failed with status {result.returncode}. "
    f"stdout={result.stdout!r}, stderr={result.stderr!r}"
)
assert os.path.isfile(trace), "The executed script produced no flock trace"
with open(trace, "r", encoding="utf-8") as f:
    calls = json.load(f)

candidates = set()
source_contents = {}
for root, dirs, files in os.walk(spool):
    for name in files:
        if name.endswith((".txt", ".csv", ".json")):
            path = os.path.abspath(os.path.join(root, name))
            candidates.add(path)
            with open(path, "r", encoding="utf-8") as src:
                source_contents[path] = src.read()

expected_skipped = set(fixed_locked + [exclusive_path])
expected_processed = candidates - expected_skipped
required_flags = fcntl.LOCK_SH | fcntl.LOCK_NB
attempted = {
    entry.get("path") for entry in calls
    if (int(entry.get("operation", 0)) & required_flags) == required_flags
}
assert candidates <= attempted, (
    "The script did not attempt fcntl.flock with LOCK_SH | LOCK_NB for every "
    f"candidate file; missing {sorted(candidates - attempted)}"
)

assert os.path.isfile(skipped), f"File {skipped} was not created"
with open(skipped, "r", encoding="utf-8") as f:
    skipped_lines = [line.strip() for line in f if line.strip()]
assert len(skipped_lines) == len(set(skipped_lines)), "skipped_logs.txt contains duplicates"
assert set(skipped_lines) == expected_skipped, (
    f"Expected dynamically locked files {expected_skipped}, got {set(skipped_lines)}"
)

assert os.path.isfile(archive), f"File {archive} was not created"
with open(archive, "r", encoding="utf-8") as f:
    archive_lines = [line.strip() for line in f if line.strip()]
assert len(archive_lines) == len(expected_processed), (
    f"Expected {len(expected_processed)} archive records, got {len(archive_lines)}"
)
records = {}
for line in archive_lines:
    obj = json.loads(line)
    assert set(obj) == {"file", "content"}, f"Archive object has incorrect keys: {set(obj)}"
    assert isinstance(obj["file"], str) and isinstance(obj["content"], str)
    assert obj["file"] not in records, f"Duplicate archive record for {obj['file']}"
    records[obj["file"]] = obj["content"]
assert set(records) == expected_processed, (
    f"Archived paths differ from recursively discovered unlocked files: "
    f"missing={expected_processed - set(records)}, extra={set(records) - expected_processed}"
)

email_pattern = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.com\b")
for path in expected_processed:
    expected_content = email_pattern.sub("[REDACTED]", source_contents[path])
    assert records[path] == expected_content, (
        f"Content for {path} was not read and redacted exactly as required"
    )
assert token in records[os.path.join(dynamic_dir, "dynamic.txt")]
assert shared_path in records, "A file under a compatible shared lock was incorrectly skipped"
assert exclusive_path not in records, "An exclusively locked file was archived"
assert os.path.join(dynamic_dir, "ignored.log") not in records, "Unsupported extension was archived"

for fd in held:
    try:
        fcntl.flock(fd, fcntl.LOCK_UN)
    except OSError:
        pass
    fd.close()
DYNAMIC_EOF
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
