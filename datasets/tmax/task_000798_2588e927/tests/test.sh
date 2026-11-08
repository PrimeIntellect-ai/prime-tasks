#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/guarded_redirect_runner.py
import os
import sys

agent_script = "/home/user/safe_redirect.py"
with open(agent_script, "rb") as f:
    source = f.read()

# The submitted implementation may use Python and its standard library, but it
# may not delegate its answer to another process, native library, or service.
def audit_hook(event, args):
    denied = {
        "os.system", "os.exec", "os.fork", "os.forkpty", "os.posix_spawn",
        "os.posix_spawnp", "subprocess.Popen", "pty.spawn",
        "ctypes.dlopen", "ctypes.dlsym", "ctypes.dlsym/handle",
        "mmap.__new__",
    }
    if event in denied or event.startswith("socket."):
        raise PermissionError("external delegation is disabled during verification")

sys.addaudithook(audit_hook)
sys.argv = [agent_script] + sys.argv[1:]
exec(compile(source, agent_script, "exec"), {"__name__": "__main__", "__file__": agent_script})
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import string
import subprocess

EXPECTED_ACCESS_LOG = '''10.0.5.12 - - [10/Oct/2023:13:55:36 -0700] "GET /login?next=http://evil.com/ HTTP/1.1" 302 123
192.168.1.105 - - [10/Oct/2023:14:00:12 -0700] "GET /login?next=https://evil.com/login HTTP/1.1" 302 123
203.0.113.42 - - [10/Oct/2023:14:15:00 -0700] "GET /login?next=//evil.com/ HTTP/1.1" 302 123
127.0.0.1 - - [10/Oct/2023:14:20:00 -0700] "GET /login?next=/dashboard HTTP/1.1" 302 123
'''


def test_evidence_extracted():
    evidence_dir = "/home/user/evidence"
    access_path = os.path.join(evidence_dir, "access.log")
    extracted_oracle = os.path.join(evidence_dir, "oracle_redirect")
    verifier_oracle = "/verifier/oracle_redirect"

    assert os.path.isdir(evidence_dir), "Evidence directory not found"
    assert os.path.isfile(access_path), "access.log not extracted"
    assert os.path.isfile(extracted_oracle), "oracle_redirect not extracted"

    with open(access_path, "r") as f:
        assert f.read() == EXPECTED_ACCESS_LOG, "Extracted access.log has incorrect contents"
    with open(extracted_oracle, "rb") as f:
        extracted_bytes = f.read()
    with open(verifier_oracle, "rb") as f:
        verifier_bytes = f.read()
    assert extracted_bytes == verifier_bytes, "Extracted oracle_redirect is not the evidence artifact"
    assert os.access(extracted_oracle, os.X_OK), "Extracted oracle_redirect is not executable"


def test_evil_ips_extracted():
    expected_ips = ["10.0.5.12", "192.168.1.105", "203.0.113.42"]
    evil_ips_path = "/home/user/evil_ips.txt"
    assert os.path.isfile(evil_ips_path), f"{evil_ips_path} not found"

    with open(evil_ips_path, "r") as f:
        ips = [line.strip() for line in f if line.strip()]

    assert ips == expected_ips, f"Expected IPs {expected_ips}, but got {ips}"


def generate_fuzz_inputs(n):
    random.seed(42)
    inputs = []

    def random_string(min_len=1, max_len=20):
        length = random.randint(min_len, max_len)
        return ''.join(random.choices(string.ascii_letters + string.digits + "-._~", k=length))

    for _ in range(n):
        choice = random.random()
        if choice < 0.50:
            schemes = ["http", "https", "ftp", "", "javascript", "data"]
            scheme = random.choice(schemes)
            netloc = random_string() + ".com" if random.random() > 0.5 else ""
            path = "/" + random_string()
            query = f"a={random_string()}&token={random_string()}" if random.random() > 0.5 else ""
            url = ""
            if scheme:
                url += f"{scheme}://"
            if netloc:
                url += netloc
            url += path
            if query:
                url += f"?{query}"
            inputs.append(url)
        elif choice < 0.70:
            prefix = random.choice(["//", "/\\", "\\\\", "\\/"])
            domain = random_string() + ".com"
            path = "/" + random_string()
            inputs.append(f"{prefix}{domain}{path}")
        elif choice < 0.90:
            path = "/" + random_string()
            query = f"user={random.randint(1, 100)}&token={random_string()}" if random.random() > 0.5 else f"user={random.randint(1,100)}"
            inputs.append(f"{path}?{query}")
        else:
            length = random.randint(1, 200)
            inputs.append(''.join(random.choices(string.printable, k=length)))

    return inputs


def test_safe_redirect_fuzz_equivalence():
    agent_script = "/home/user/safe_redirect.py"
    oracle_binary = "/verifier/oracle_redirect"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert not os.path.islink(agent_script), "Agent script must not be a symlink"
    assert stat.S_ISREG(os.lstat(agent_script).st_mode), "Agent script must be a regular file"
    assert os.path.isfile(oracle_binary), f"Oracle binary not found at {oracle_binary}"

    inputs = generate_fuzz_inputs(1000)

    for inp in inputs:
        oracle_proc = subprocess.run(
            [oracle_binary, inp],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert oracle_proc.returncode == 0, f"Oracle failed for input: {repr(inp)}"
        oracle_out = oracle_proc.stdout.strip()

        agent_proc = subprocess.run(
            ["python3", "/tmp/guarded_redirect_runner.py", inp],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert agent_proc.returncode == 0, (
            f"Agent failed for input: {repr(inp)}\n"
            f"stderr: {agent_proc.stderr!r}"
        )
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Output mismatch for input: {repr(inp)}\n"
            f"Oracle output: {repr(oracle_out)}\n"
            f"Agent output: {repr(agent_out)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
