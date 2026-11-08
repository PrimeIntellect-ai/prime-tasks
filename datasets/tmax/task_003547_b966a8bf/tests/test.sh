#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import shutil
import stat
import string
import uuid


def test_scripts_exist_and_executable():
    analyze_script = "/home/user/analyze.sh"
    isolation_script = "/home/user/run_isolation.sh"

    # Check analyze.sh
    assert os.path.exists(analyze_script), f"{analyze_script} does not exist."
    assert os.path.isfile(analyze_script), f"{analyze_script} is not a file."
    st = os.stat(analyze_script)
    assert bool(st.st_mode & stat.S_IXUSR), f"{analyze_script} is not executable."

    # Check run_isolation.sh
    assert os.path.exists(isolation_script), f"{isolation_script} does not exist."
    assert os.path.isfile(isolation_script), f"{isolation_script} is not a file."
    st = os.stat(isolation_script)
    assert bool(st.st_mode & stat.S_IXUSR), f"{isolation_script} is not executable."


def test_isolation_script_content():
    isolation_script = "/home/user/run_isolation.sh"
    with open(isolation_script, 'r') as f:
        content = f.read()

    assert "unshare" in content, f"{isolation_script} does not use the 'unshare' command."
    # Check for user and network isolation flags
    has_user_flag = "-r" in content or "--map-root-user" in content or "-U" in content or "--user" in content
    has_net_flag = "-n" in content or "--net" in content
    assert has_user_flag and has_net_flag, f"{isolation_script} must use unshare with user and network isolation flags (e.g., -r -n)."


def test_audit_trail_content():
    audit_trail = "/home/user/audit_trail.csv"
    assert os.path.exists(audit_trail), f"{audit_trail} does not exist."
    assert os.path.isfile(audit_trail), f"{audit_trail} is not a file."

    expected_lines = [
        "LOG-001,XSS,True,<script>alert(1)</script>",
        "LOG-002,None,False,SELECT * FROM users;",
        "LOG-003,SQLi,False,' OR 1=1 --",
        "LOG-004,None,False,hello world",
        "LOG-005,XSS,True,<img src=x onerror=alert(1)>",
        "LOG-006,SQLi,False,UNION SELECT username, password FROM admins"
    ]

    with open(audit_trail, 'r') as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_lines, f"Contents of {audit_trail} do not match the expected audit trail."


def test_pipeline_executes_unshare_and_handles_unseen_inputs():
    raw_path = "/home/user/raw_logs.txt"
    audit_path = "/home/user/audit_trail.csv"
    runner = "/home/user/run_isolation.sh"

    with open(raw_path, "rb") as f:
        original_raw = f.read()
    original_audit = None
    if os.path.exists(audit_path):
        with open(audit_path, "rb") as f:
            original_audit = f.read()

    nonce = uuid.uuid4().hex
    payloads = [
        f"ordinary request {nonce}",
        f"alpha,beta {nonce}",
        f"prefix <script data-x={nonce}>alert(9)</script>",
        f"url=javascript:alert('{nonce}')",
        f"<img src=x onerror=notify('{nonce}')>",
        f"UNION SELECT secret_{nonce} FROM vault",
        f"name=' OR 1=1 and marker={nonce}",
        f"SELECT UNION then SELECT separately {nonce}",
        f"SCRIPT and union select are lower case {nonce}",
        f"spaces before and after marker {nonce}",
        f"safe punctuation !@#$%^&*() {nonce}",
    ]
    random.SystemRandom().shuffle(payloads)

    records = []
    expected = []
    for index, payload in enumerate(payloads):
        log_id = f"DYN-{nonce[:10]}-{index:02d}"
        encoded = base64.b64encode(payload.encode("utf-8")).decode("ascii")
        records.append(f"{log_id}:{encoded}")
        if any(marker in payload for marker in ("<script", "javascript:", "onerror=")):
            threat, blocked = "XSS", "True"
        elif any(marker in payload for marker in ("UNION SELECT", "' OR 1=1")):
            threat, blocked = "SQLi", "False"
        else:
            threat, blocked = "None", "False"
        expected.append(f"{log_id},{threat},{blocked},{payload}")

    unshare = shutil.which("unshare")
    assert unshare, "The required unshare utility is not installed."
    unshare = os.path.realpath(unshare)
    backup = unshare + ".verifier-backup-" + uuid.uuid4().hex
    invocation_log = "/tmp/unshare-invocation-" + uuid.uuid4().hex + ".json"
    token = uuid.uuid4().hex

    wrapper = r'''#!/usr/bin/python3
import json
import os
import subprocess
import sys

args = sys.argv[1:]
with open(os.environ["VERIFIER_UNSHARE_LOG"], "w") as f:
    json.dump({"token": os.environ.get("VERIFIER_UNSHARE_TOKEN"), "args": args}, f)

user_flag = False
net_flag = False
positionals = []
after_options = False
for arg in args:
    if after_options:
        positionals.append(arg)
    elif arg == "--":
        after_options = True
    elif arg.startswith("--"):
        name = arg.split("=", 1)[0]
        if name in ("--user", "--map-root-user"):
            user_flag = True
        if name == "--net":
            net_flag = True
    elif arg.startswith("-") and arg != "-":
        flags = arg[1:]
        if "U" in flags or "r" in flags:
            user_flag = True
        if "n" in flags:
            net_flag = True
    else:
        after_options = True
        positionals.append(arg)

valid_command = bool(positionals) and (
    positionals[0] == "/home/user/analyze.sh" or
    (os.path.basename(positionals[0]) in ("bash", "sh") and "/home/user/analyze.sh" in positionals[1:])
)
if not (user_flag and net_flag and valid_command):
    sys.exit(97)

sys.exit(subprocess.run(["/home/user/analyze.sh"], env=os.environ.copy()).returncode)
'''

    replaced = False
    try:
        with open(raw_path, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(records) + "\n")
        if os.path.exists(audit_path):
            os.unlink(audit_path)

        os.rename(unshare, backup)
        replaced = True
        with open(unshare, "w", encoding="utf-8", newline="\n") as f:
            f.write(wrapper)
        os.chmod(unshare, 0o755)

        env = os.environ.copy()
        env["VERIFIER_UNSHARE_LOG"] = invocation_log
        env["VERIFIER_UNSHARE_TOKEN"] = token
        result = __import__("subprocess").run(
            [runner], env=env, stdout=__import__("subprocess").PIPE,
            stderr=__import__("subprocess").PIPE, text=True, timeout=20
        )
        assert result.returncode == 0, (
            f"run_isolation.sh failed while executing the analysis pipeline: {result.stderr}"
        )
        assert os.path.exists(invocation_log), "run_isolation.sh did not execute the unshare command."
        with open(invocation_log, "r", encoding="utf-8") as f:
            invocation = json.load(f)
        assert invocation.get("token") == token, "Invalid unshare invocation record."

        assert os.path.isfile(audit_path), "The pipeline did not generate audit_trail.csv."
        with open(audit_path, "r", encoding="utf-8") as f:
            actual = f.read().splitlines()
        assert actual == expected, "The pipeline failed on dynamically generated log records."
    finally:
        if replaced:
            try:
                if os.path.exists(unshare):
                    os.unlink(unshare)
            finally:
                os.rename(backup, unshare)
        if os.path.exists(invocation_log):
            os.unlink(invocation_log)
        with open(raw_path, "wb") as f:
            f.write(original_raw)
        if original_audit is None:
            if os.path.exists(audit_path):
                os.unlink(audit_path)
        else:
            with open(audit_path, "wb") as f:
                f.write(original_audit)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
