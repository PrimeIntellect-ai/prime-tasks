#!/bin/bash
set -u
mkdir -p /logs/verifier

run_verification() {
    set -e

    SANDBOX="$(mktemp -d /root/replica-sandbox.XXXXXX)"
    export SANDBOX
    trap 'rm -rf "$SANDBOX"' RETURN

    mkdir -p "$SANDBOX/usr/bin" "$SANDBOX/usr/lib" "$SANDBOX/lib" "$SANDBOX/lib64" "$SANDBOX/tmp"
    chmod 755 "$SANDBOX" "$SANDBOX/tmp"
    cp -L /usr/bin/python3 "$SANDBOX/usr/bin/python3"

    PY_STDLIB="$(python3 -c 'import sysconfig; print(sysconfig.get_path("stdlib"))')"
    mkdir -p "$SANDBOX$(dirname "$PY_STDLIB")"
    cp -a "$PY_STDLIB" "$SANDBOX$(dirname "$PY_STDLIB")/"

    {
        ldd /usr/bin/python3
        find "$PY_STDLIB" -type f -name '*.so' -exec ldd {} \; 2>/dev/null || true
    } | awk '/=> \/[^ ]+/ {print $3} /^\/[^^[:space:]]*[[:space:]]/ {print $1}' | sort -u | while read -r lib; do
        if [ -f "$lib" ]; then
            mkdir -p "$SANDBOX$(dirname "$lib")"
            cp -L "$lib" "$SANDBOX$lib"
        fi
    done

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import shutil
import stat
import subprocess
import pytest

ORACLE = "/app/suspicious_bin"
REPLICA = "/home/user/replica.py"
SANDBOX = os.environ["SANDBOX"]


def expected_value(value):
    ts = int(value)
    days = ts // 86400
    year = 1970 + (days // 365)
    leap_days = (year - 1968) // 4
    modified_days = days + leap_days
    return str((modified_days * 104729) % 1000000007)


def test_deleted_logs_recovered():
    expected = {
        "/app/logs/beacon1.log": "1609459200",
        "/app/logs/beacon2.log": "1612137600",
    }
    for path, contents in expected.items():
        assert os.path.exists(path), f"Recovered log {path} is missing."
        assert stat.S_ISREG(os.stat(path).st_mode), f"Recovered log {path} is not a regular file."
        with open(path, "r", encoding="utf-8") as handle:
            assert handle.read().strip() == contents, f"Recovered log {path} has incorrect contents."


def test_replica_fuzz_equivalence():
    assert os.path.exists(ORACLE), f"Oracle binary {ORACLE} is missing."
    assert os.access(ORACLE, os.X_OK), f"Oracle binary {ORACLE} is not executable."
    assert os.path.exists(REPLICA), f"Replica script {REPLICA} is missing."
    assert stat.S_ISREG(os.stat(REPLICA).st_mode), "Replica must be a regular Python source file."
    with open(REPLICA, "rb") as handle:
        assert handle.read(4) != b"\x7fELF", "Replica must be a Python script, not a copied executable."

    random.seed(42)
    test_inputs = [str(random.randint(1, 2147483647)) for _ in range(10000)]
    test_inputs.extend(["0", "1", "86400", "31536000", "2147483647"])

    oracle_outputs = {}
    for val in test_inputs:
        try:
            result = subprocess.run(
                [ORACLE, val], capture_output=True, text=True, timeout=1, check=True
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {val}")
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"Oracle failed on input {val} with error: {exc.stderr}")
        oracle_outputs[val] = result.stdout.strip()
        assert oracle_outputs[val] == expected_value(val), f"Oracle produced an unexpected result on {val}."

    sandbox_replica = os.path.join(SANDBOX, "replica.py")
    shutil.copyfile(REPLICA, sandbox_replica)
    os.chmod(sandbox_replica, 0o444)

    account = pwd.getpwnam("user")

    def enter_sandbox():
        os.chroot(SANDBOX)
        os.chdir("/")
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    env = {
        "PATH": "/usr/bin",
        "PYTHONDONTWRITEBYTECODE": "1",
        "PYTHONNOUSERSITE": "1",
        "LC_ALL": "C",
    }

    for val in test_inputs:
        try:
            result = subprocess.run(
                ["/usr/bin/python3", "/replica.py", val],
                capture_output=True,
                text=True,
                timeout=1,
                check=True,
                preexec_fn=enter_sandbox,
                env=env,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Replica script timed out on input {val}")
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"Replica script failed on input {val} with error: {exc.stderr}")

        replica_output = result.stdout.strip()
        assert oracle_outputs[val] == replica_output, (
            f"Mismatch on input {val}. Oracle output: {oracle_outputs[val]}, "
            f"Replica output: {replica_output}"
        )
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
}

if run_verification 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
