#!/bin/bash
set -e
mkdir -p /logs/verifier

oracle_path=/app/waf_evasion_encoder
oracle_backup=/root/.waf_evasion_encoder.verifier.$$

cleanup() {
    if [ -f "$oracle_backup" ]; then
        mv -f "$oracle_backup" "$oracle_path"
    fi
}
trap cleanup EXIT

# The oracle was available for reverse engineering, but must not be available
# while the submitted standalone implementation is being exercised.
mv "$oracle_path" "$oracle_backup"
chmod 700 "$oracle_backup"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import pwd
import random
import re
import string
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/craft_payload.sh"
SALT = b"_WAF_BYPASS_S4LT_2024"


def test_craft_payload_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def expected_output(payload):
    encoded = base64.b64encode(payload[::-1].encode("ascii"))
    token = hashlib.md5(encoded + SALT).hexdigest()
    return f"[AUTH-TOKEN: {token}]|PAYLOAD:{encoded.decode('ascii')}\n"


def package_md5s():
    trusted = {}
    info_dir = "/var/lib/dpkg/info"
    for name in os.listdir(info_dir):
        if not name.endswith(".md5sums"):
            continue
        try:
            with open(os.path.join(info_dir, name), encoding="utf-8") as f:
                for line in f:
                    digest, relpath = line.rstrip("\n").split(None, 1)
                    path = "/" + relpath.lstrip("/")
                    trusted[os.path.realpath(path)] = digest
        except (OSError, ValueError):
            continue
    return trusted


TRUSTED_MD5 = package_md5s()


def file_md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.hexdigest()


def assert_only_packaged_tools_executed(trace_path):
    with open(trace_path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if not re.search(r"=\s*0\s*$", line):
                continue
            match = re.search(r'\bexecve(?:at)?\([^\"]*\"((?:\\.|[^\"\\])*)\"', line)
            if not match:
                continue
            executed = json.loads('"' + match.group(1) + '"')
            assert os.path.isabs(executed), f"Submission executed an untrusted program: {executed}"
            resolved = os.path.realpath(executed)
            basename = os.path.basename(resolved)
            assert not (basename.startswith("ld-linux") or basename == "ld.so"), \
                f"Submission delegated through the dynamic loader: {executed}"
            expected_md5 = TRUSTED_MD5.get(resolved)
            assert expected_md5 is not None, \
                f"Submission executed a non-package program instead of being standalone: {executed}"
            assert file_md5(resolved) == expected_md5, \
                f"Submission executed a modified system program: {executed}"


def run_agent(payload):
    user = pwd.getpwnam("user")
    fd, trace_path = tempfile.mkstemp(prefix="craft_payload_trace_", dir="/tmp")
    os.close(fd)
    os.chown(trace_path, user.pw_uid, user.pw_gid)
    os.chmod(trace_path, 0o600)

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    env = os.environ.copy()
    env["HOME"] = user.pw_dir
    env["PATH"] = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    try:
        result = subprocess.run(
            ["/usr/bin/strace", "-f", "-qq", "-e", "trace=execve,execveat",
             "-o", trace_path, "/usr/bin/bash", SCRIPT_PATH, payload],
            capture_output=True,
            text=True,
            env=env,
            preexec_fn=demote,
        )
        assert_only_packaged_tools_executed(trace_path)
        return result
    finally:
        os.unlink(trace_path)


def test_fuzz_equivalence():
    random.seed(42)
    charset = string.ascii_letters + string.digits + string.punctuation + " "

    for i in range(100):
        length = random.randint(1, 200)
        payload = "".join(random.choice(charset) for _ in range(length))
        agent_res = run_agent(payload)

        assert agent_res.returncode == 0, \
            f"Agent script failed on input: {payload!r}\nStderr: {agent_res.stderr}"

        expected = expected_output(payload).strip()
        agent_out = agent_res.stdout.strip()
        assert expected == agent_out, (
            f"Mismatch on iteration {i + 1} with input: {payload!r}\n"
            f"Expected: {expected}\n"
            f"Got:      {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
