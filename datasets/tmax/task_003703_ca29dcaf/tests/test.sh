#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import stat
import subprocess

DEPLOY = "/home/user/deploy.sh"
SOURCE = "/home/user/probe_ssh.go"
PROBE = "/home/user/probe_ssh"
ALERTS = "/home/user/alerts.log"
MOCK = "/home/user/mock_ssh"
EXPECTED = '{"event":"key_rejected","target":"jumphost"}'
EXPECTED_MOCK = b'''#!/bin/bash
if [ "$1" != "jumpuser@jumphost" ]; then
    echo "Usage: mock_ssh jumpuser@jumphost"
    exit 1
fi
echo "Attempting public key authentication..."
sleep 0.2
echo "Public key rejected. Fallback to password."
echo -n "password: "
read -r pass
if [ "$pass" = "probe_pass" ]; then
    echo "Access granted."
    exit 0
else
    echo "Access denied."
    exit 1
fi
'''

def as_user(*args, timeout=30):
    return subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", *args],
        capture_output=True,
        text=True,
        timeout=timeout,
    )

def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.hexdigest()

def state(path):
    s = os.stat(path)
    return (stat.S_IMODE(s.st_mode), s.st_uid, s.st_gid, s.st_size, digest(path))

def assert_one_exact_alert():
    with open(ALERTS, "rb") as f:
        data = f.read()
    assert data in (EXPECTED.encode(), (EXPECTED + "\n").encode()), \
        f"Fail: alerts.log is not exactly one expected JSON line: {data!r}"

def test_deploy_script_exists():
    assert os.path.exists(DEPLOY), f"Fail: {DEPLOY} does not exist."
    assert os.path.isfile(DEPLOY), f"Fail: {DEPLOY} is not a file."
    assert os.path.isfile(SOURCE), f"Fail: {SOURCE} does not exist or is not a file."
    with open(MOCK, "rb") as f:
        assert f.read() == EXPECTED_MOCK, "Fail: /home/user/mock_ssh was modified."
    assert os.access(MOCK, os.X_OK), "Fail: /home/user/mock_ssh is not executable."

def test_deploy_script_execution_and_idempotency():
    result1 = as_user("bash", DEPLOY)
    assert result1.returncode == 0, f"Fail: deploy.sh failed on first run. Stderr: {result1.stderr}"

    assert os.path.exists(PROBE), f"Fail: {PROBE} executable not found."
    assert os.path.isfile(PROBE), f"Fail: {PROBE} is not a regular file."
    assert os.access(PROBE, os.X_OK), f"Fail: {PROBE} is not executable."

    assert os.path.exists(ALERTS), f"Fail: {ALERTS} was not created."
    perms = oct(os.stat(ALERTS).st_mode)[-3:]
    assert perms == "600", f"Fail: incorrect permissions on alerts.log ({perms} instead of 600)."

    with open(PROBE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Fail: probe_ssh is not a compiled ELF executable."
    build_info = subprocess.run(["go", "version", "-m", PROBE], capture_output=True, text=True)
    assert build_info.returncode == 0 and "go1" in build_info.stdout, \
        f"Fail: probe_ssh does not contain Go build information: {build_info.stdout} {build_info.stderr}"

    independent = as_user("go", "build", "-o", "/tmp/verifier_probe_ssh", SOURCE, timeout=60)
    assert independent.returncode == 0, f"Fail: probe_ssh.go does not compile as Go. Stderr: {independent.stderr}"

    before = {p: state(p) for p in (DEPLOY, SOURCE, PROBE, ALERTS)}
    result2 = as_user("bash", DEPLOY)
    assert result2.returncode == 0, f"Fail: deploy.sh is not idempotent (exited non-zero). Stderr: {result2.stderr}"
    after = {p: state(p) for p in (DEPLOY, SOURCE, PROBE, ALERTS)}
    assert after == before, "Fail: a second deployment changed deployed file contents, ownership, or permissions."

def test_prober_execution_and_alert():
    open(ALERTS, "wb").close()
    os.chmod(ALERTS, 0o600)
    result = as_user(PROBE, timeout=10)
    assert result.returncode == 0, f"Fail: probe_ssh exited with non-zero code. Stderr: {result.stderr}"
    assert os.path.exists(ALERTS), f"Fail: {ALERTS} does not exist."
    assert_one_exact_alert()
    assert stat.S_IMODE(os.stat(ALERTS).st_mode) == 0o600, "Fail: prober changed alerts.log permissions."

def test_prober_actually_drives_mock_and_only_alerts_on_exact_output():
    with open(MOCK, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(MOCK).st_mode)
    trace = "/tmp/probe_ssh_verifier_trace"

    no_trigger = r'''#!/bin/bash
printf 'argc=%s arg1=%s\n' "$#" "${1-}" >> /tmp/probe_ssh_verifier_trace
[ "$#" -eq 1 ] && [ "$1" = "jumpuser@jumphost" ] || exit 41
printf '%s\n' 'Public key rejected. Fallback to passwords.'
printf 'password: '
IFS= read -r pass || exit 42
printf 'pass=%s\n' "$pass" >> /tmp/probe_ssh_verifier_trace
[ "$pass" = "probe_pass" ] || exit 43
exit 0
'''
    trigger = r'''#!/bin/bash
printf 'argc=%s arg1=%s\n' "$#" "${1-}" >> /tmp/probe_ssh_verifier_trace
[ "$#" -eq 1 ] && [ "$1" = "jumpuser@jumphost" ] || exit 51
printf 'Public key rejected. '
sleep 0.15
printf 'Fallback to password.\n'
found=0
for i in $(seq 1 100); do
    data=$(cat /home/user/alerts.log 2>/dev/null; printf x)
    expected='{"event":"key_rejected","target":"jumphost"}'
    if [ "$data" = "${expected}x" ] || [ "$data" = "${expected}
x" ]; then
        found=1
        break
    fi
    sleep 0.05
done
[ "$found" -eq 1 ] || exit 52
printf 'password: '
IFS= read -r pass || exit 53
printf 'pass=%s\n' "$pass" >> /tmp/probe_ssh_verifier_trace
[ "$pass" = "probe_pass" ] || exit 54
printf '%s\n' 'Access granted.'
exit 0
'''

    try:
        with open(trace, "w") as f:
            pass
        os.chmod(trace, 0o666)
        with open(MOCK, "w") as f:
            f.write(no_trigger)
        os.chmod(MOCK, 0o755)
        open(ALERTS, "wb").close()
        os.chmod(ALERTS, 0o600)
        result = as_user(PROBE, timeout=10)
        assert result.returncode == 0, f"Fail: prober did not cleanly handle the non-triggering interactive mock: {result.stderr}"
        with open(ALERTS, "rb") as f:
            assert f.read() == b"", "Fail: prober alerted when the exact rejection string was absent."
        with open(trace) as f:
            first_trace = f.read().splitlines()
        assert first_trace == ["argc=1 arg1=jumpuser@jumphost", "pass=probe_pass"], \
            f"Fail: wrong mock command or password interaction: {first_trace!r}"

        with open(trace, "w") as f:
            pass
        with open(MOCK, "w") as f:
            f.write(trigger)
        os.chmod(MOCK, 0o755)
        open(ALERTS, "wb").close()
        os.chmod(ALERTS, 0o600)
        result = as_user(PROBE, timeout=10)
        assert result.returncode == 0, f"Fail: prober did not detect output and complete the password exchange: {result.stderr}"
        assert_one_exact_alert()
        with open(trace) as f:
            second_trace = f.read().splitlines()
        assert second_trace == ["argc=1 arg1=jumpuser@jumphost", "pass=probe_pass"], \
            f"Fail: wrong mock command or password interaction: {second_trace!r}"
    finally:
        with open(MOCK, "wb") as f:
            f.write(original)
        os.chmod(MOCK, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
