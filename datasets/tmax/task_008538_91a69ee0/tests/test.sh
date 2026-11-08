#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import uuid


def test_v2_db_exists_and_content():
    path = "/home/user/v2.db"
    assert os.path.exists(path), f"Missing {path}"
    with open(path, "r") as f:
        content = f.read().strip()

    expected_content = "1,admin,alice,true\n2,user,bob,true\n3,moderator,charlie,true"
    assert content == expected_content, f"Content of {path} is incorrect. Got:\n{content}"


def test_test_log_exists_and_content():
    path = "/home/user/test.log"
    assert os.path.exists(path), f"Missing {path}"
    with open(path, "r") as f:
        content = f.read().strip()

    expected_content = "Test suite passed: verified 3 entities.\nSUCCESS"
    assert content == expected_content, f"Content of {path} is incorrect. Got:\n{content}"


def test_orchestrate_script_exists_and_executable():
    path = "/home/user/orchestrate.sh"
    assert os.path.exists(path), f"Missing {path}"

    st = os.stat(path)
    assert stat.S_ISREG(st.st_mode), f"{path} is not a regular file"
    assert bool(st.st_mode & stat.S_IXUSR), f"{path} is not executable"


def test_orchestrate_script_max_cores_constraint():
    path = "/home/user/orchestrate.sh"

    # Test with MAX_CORES=4 (should fail)
    env = os.environ.copy()
    env["MAX_CORES"] = "4"
    result = subprocess.run([path], env=env, capture_output=True)
    assert result.returncode == 1, "Script should exit with status 1 when MAX_CORES >= 4"

    # Test with MAX_CORES=5 (should fail)
    env["MAX_CORES"] = "5"
    result = subprocess.run([path], env=env, capture_output=True)
    assert result.returncode == 1, "Script should exit with status 1 when MAX_CORES >= 4"


def test_orchestrate_script_success_run():
    path = "/home/user/orchestrate.sh"

    # Remove artifacts to ensure the script recreates them correctly
    if os.path.exists("/home/user/v2.db"):
        os.remove("/home/user/v2.db")
    if os.path.exists("/home/user/test.log"):
        os.remove("/home/user/test.log")

    # Test with MAX_CORES=1 (should succeed)
    env = os.environ.copy()
    env["MAX_CORES"] = "1"
    result = subprocess.run([path], env=env, capture_output=True)
    assert result.returncode == 0, f"Script failed with MAX_CORES=1. Stderr: {result.stderr.decode()}"

    # Verify artifacts are recreated correctly
    assert os.path.exists("/home/user/v2.db"), "Script did not create /home/user/v2.db"
    assert os.path.exists("/home/user/test.log"), "Script did not create /home/user/test.log"

    with open("/home/user/test.log", "r") as f:
        content = f.read().strip()
    assert "SUCCESS" in content, "test.log did not contain SUCCESS after a successful run"


def _snapshot(path):
    if not os.path.exists(path):
        return None
    st = os.stat(path)
    with open(path, "rb") as f:
        return f.read(), stat.S_IMODE(st.st_mode)


def _restore(path, snapshot):
    if snapshot is None:
        if os.path.lexists(path):
            os.remove(path)
        return
    data, mode = snapshot
    if os.path.lexists(path):
        os.remove(path)
    with open(path, "wb") as f:
        f.write(data)
    os.chmod(path, mode)


def _expected_v2(rows):
    return "".join(f"{row_id},{role},{name},true\n" for row_id, name, role in rows)


def _install_tester(marker, token, expected_cores, exit_code):
    tester = "/home/user/bin/e2e_tester"
    script = f'''#!/bin/bash
printf '%s\\n' invoked > '{marker}'
if [ "$#" -ne 1 ] || [ "$1" != "/home/user/v2.db" ]; then
    echo "wrong tester arguments"
    exit 91
fi
if [ "$MAX_CORES" != "{expected_cores}" ]; then
    echo "wrong MAX_CORES"
    exit 92
fi
printf '%s\\n' '{token}'
exit {exit_code}
'''
    if os.path.lexists(tester):
        os.remove(tester)
    with open(tester, "w") as f:
        f.write(script)
    os.chmod(tester, 0o755)


def test_dynamic_migration_default_and_tester_outcomes():
    orchestrator = "/home/user/orchestrate.sh"
    paths = [
        "/home/user/v1.db",
        "/home/user/v2.db",
        "/home/user/test.log",
        "/home/user/bin/e2e_tester",
    ]
    saved = {path: _snapshot(path) for path in paths}
    marker = f"/tmp/e2e-invoked-{uuid.uuid4().hex}"

    try:
        # Exercise migration on data unknown while the agent was running, verify
        # the unset-variable default is exported, and prove the required tester
        # is executed with exactly the migrated database argument.
        nonce = uuid.uuid4().hex
        rows = [
            ("17", f"name_{nonce[:8]}", f"role_{nonce[8:16]}"),
            ("204", f"name_{nonce[16:24]}", f"role_{nonce[24:32]}"),
        ]
        with open("/home/user/v1.db", "w") as f:
            for row in rows:
                f.write(",".join(row) + "\n")
        token = f"tester-success-{uuid.uuid4().hex}"
        _install_tester(marker, token, "2", 0)
        for artifact in ("/home/user/v2.db", "/home/user/test.log", marker):
            if os.path.exists(artifact):
                os.remove(artifact)

        env = os.environ.copy()
        env.pop("MAX_CORES", None)
        result = subprocess.run([orchestrator], env=env, capture_output=True)
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert os.path.exists(marker), "orchestrate.sh did not execute /home/user/bin/e2e_tester"
        with open("/home/user/v2.db") as f:
            assert f.read() == _expected_v2(rows)
        with open("/home/user/test.log") as f:
            assert f.read().splitlines() == [token, "SUCCESS"]

        # Exercise a non-zero tester result on another independently generated
        # database and require its stdout plus the literal FAILURE line.
        nonce = uuid.uuid4().hex
        rows = [
            ("8", f"person_{nonce[:10]}", f"group_{nonce[10:20]}"),
            ("99", f"person_{nonce[20:26]}", f"group_{nonce[26:32]}"),
            ("501", f"person_{nonce[3:13]}", f"group_{nonce[13:23]}"),
        ]
        with open("/home/user/v1.db", "w") as f:
            for row in rows:
                f.write(",".join(row) + "\n")
        token = f"tester-failure-{uuid.uuid4().hex}"
        _install_tester(marker, token, "3", 23)
        for artifact in ("/home/user/v2.db", "/home/user/test.log", marker):
            if os.path.exists(artifact):
                os.remove(artifact)

        env = os.environ.copy()
        env["MAX_CORES"] = "3"
        subprocess.run([orchestrator], env=env, capture_output=True)
        assert os.path.exists(marker), "orchestrate.sh did not invoke the tester on its failure path"
        with open("/home/user/v2.db") as f:
            assert f.read() == _expected_v2(rows)
        with open("/home/user/test.log") as f:
            assert f.read().splitlines() == [token, "FAILURE"]
    finally:
        if os.path.exists(marker):
            os.remove(marker)
        for path in paths:
            _restore(path, saved[path])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
