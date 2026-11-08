#!/bin/bash
mkdir -p /logs/verifier

fail_verifier() {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}

script_path=/home/user/math_port.sh
isolated_dir=/opt/math_port_verifier
isolated_script=$isolated_dir/math_port.sh

# Preserve the original existence/type/executable checks before isolating execution.
[[ -e "$script_path" ]] || fail_verifier
[[ -f "$script_path" ]] || fail_verifier
[[ -x "$script_path" ]] || fail_verifier
[[ -x /app/legacy_math ]] || fail_verifier

rm -rf "$isolated_dir"
mkdir -p "$isolated_dir/tmp"
cp -L -- "$script_path" "$isolated_script" || fail_verifier
chmod 755 "$isolated_dir" "$isolated_script"
chown -R root:root "$isolated_dir"
chown nobody:nogroup "$isolated_dir/tmp"
chmod 700 "$isolated_dir/tmp"

# The reference was available for investigation, but must not be callable by the
# submitted program while it is being verified.
mkdir -p /root/verifier_quarantine
chmod 700 /root/verifier_quarantine
mv /app/legacy_math /root/verifier_quarantine/legacy_math || fail_verifier

# Prevent the unprivileged test process from reaching helpers or copied binaries
# left beside the submission. The isolated script remains available under /opt.
chown root:root /home/user
chmod 700 /home/user
find /tmp /var/tmp /dev/shm -mindepth 1 -user user -exec rm -rf -- {} + 2>/dev/null || true
chmod 755 /tmp /var/tmp 2>/dev/null || true
chmod 755 /dev/shm 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import random
import subprocess

ORIGINAL_PATH = "/home/user/math_port.sh"
AGENT_PATH = "/opt/math_port_verifier/math_port.sh"


def drop_privileges():
    account = pwd.getpwnam("nobody")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def collatz_steps(n):
    steps = 0
    while n > 1:
        if n % 2 == 0:
            n //= 2
        else:
            n = 3 * n + 1
        steps += 1
    return steps


def test_math_port_script_exists_and_executable():
    assert os.path.exists(ORIGINAL_PATH), f"Script {ORIGINAL_PATH} does not exist."
    assert os.path.isfile(ORIGINAL_PATH), f"{ORIGINAL_PATH} is not a file."
    assert os.access(ORIGINAL_PATH, os.X_OK), f"Script {ORIGINAL_PATH} is not executable."

    syntax = subprocess.run(
        ["/bin/bash", "-n", AGENT_PATH], text=True, capture_output=True
    )
    assert syntax.returncode == 0, f"Submission is not valid Bash: {syntax.stderr}"


def test_fuzz_equivalence():
    random.seed(42)
    test_cases = [random.randint(1, 100000) for _ in range(100)]

    for n in test_cases:
        payload = json.dumps({"query": {"value": n}})
        expected = (
            f'{{"result": {{"initial_value": {n}, '
            f'"steps": {collatz_steps(n)}}}}}'
        )

        agent_proc = subprocess.run(
            ["/bin/bash", AGENT_PATH],
            input=payload,
            text=True,
            capture_output=True,
            env={
                "PATH": "/usr/bin:/bin",
                "HOME": "/nonexistent",
                "TMPDIR": "/opt/math_port_verifier/tmp",
                "LANG": "C",
            },
            preexec_fn=drop_privileges,
        )

        assert agent_proc.returncode == 0, (
            f"Agent script failed on input {payload}. "
            f"Stderr: {agent_proc.stderr}"
        )
        agent_output = agent_proc.stdout.strip()
        assert agent_output == expected, (
            f"Mismatch on input {payload}.\n"
            f"Expected: {expected}\n"
            f"Got: {agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
