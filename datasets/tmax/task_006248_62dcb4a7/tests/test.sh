#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import pwd
import secrets
import shutil
import stat
import subprocess


def test_parsed_services_csv():
    csv_path = "/home/user/parsed_services.csv"
    assert os.path.isfile(csv_path), f"The file {csv_path} does not exist."

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "cont-db,DB_USER=root,/home/user/mocks/run_db.sh",
        "cont-api,API_ENV=prod,/home/user/mocks/run_api.sh",
        "cont-cache,CACHE_SIZE=10,/home/user/mocks/run_cache.sh"
    ]

    assert lines == expected_lines, f"The contents of {csv_path} do not match the expected output."


def test_supervisor_script_exists():
    script_path = "/home/user/container_supervisor.py"
    assert os.path.isfile(script_path), f"The Python script {script_path} does not exist."


def test_supervisor_log():
    log_path = "/home/user/supervisor.log"
    assert os.path.isfile(log_path), f"The log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "[cont-db] SUCCESS",
        "[cont-api] SUCCESS",
        "[cont-cache] FAILED"
    ]

    assert lines == expected_lines, f"The contents of {log_path} do not match the expected output."


def test_supervisor_uses_subprocess():
    script_path = "/home/user/container_supervisor.py"
    assert os.path.getsize(script_path) > 0, "The supervisor script is empty."
    with open(script_path, "r") as f:
        tree = ast.parse(f.read(), filename=script_path)

    module_aliases = set()
    callable_aliases = set()
    subprocess_calls = {"run", "Popen", "call", "check_call", "check_output"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "subprocess":
                    module_aliases.add(alias.asname or "subprocess")
        elif isinstance(node, ast.ImportFrom) and node.module == "subprocess":
            for alias in node.names:
                if alias.name in subprocess_calls or alias.name == "*":
                    callable_aliases.add(alias.asname or alias.name)

    found_call = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute):
            if (isinstance(node.func.value, ast.Name)
                    and node.func.value.id in module_aliases
                    and node.func.attr in subprocess_calls):
                found_call = True
        elif isinstance(node.func, ast.Name):
            if node.func.id in callable_aliases or "*" in callable_aliases:
                found_call = True

    assert module_aliases or callable_aliases, "The script does not import the subprocess module."
    assert found_call, "The script does not use subprocess to execute commands."


def test_supervisor_execution_behavior():
    csv_path = "/home/user/parsed_services.csv"
    log_path = "/home/user/supervisor.log"
    script_path = "/home/user/container_supervisor.py"
    user = pwd.getpwnam("user")
    token = secrets.token_hex(8)
    workdir = f"/home/user/.supervisor_verifier_{token}"

    def snapshot(path):
        st = os.stat(path)
        with open(path, "rb") as f:
            data = f.read()
        return data, stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid

    def restore(path, saved):
        data, mode, uid, gid = saved
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
        with open(path, "wb") as f:
            f.write(data)
        os.chmod(path, mode)
        os.chown(path, uid, gid)

    saved_csv = snapshot(csv_path)
    saved_log = snapshot(log_path)
    names = [f"first-{token}", f"retry-{token}", f"fail-{token}"]
    env_names = ["VERIFY_FIRST", "VERIFY_RETRY", "VERIFY_FAIL"]
    env_values = [f"v1_{token}", f"v2_{token}", f"v3_{token}"]

    try:
        os.mkdir(workdir, 0o777)
        os.chmod(workdir, 0o777)
        commands = []
        modes = ["success", "retry", "fail"]
        for index, mode in enumerate(modes):
            command = os.path.join(workdir, f"command_{index}.sh")
            counter = os.path.join(workdir, f"count_{index}")
            if mode == "success":
                outcome = "exit 0"
            elif mode == "retry":
                outcome = 'if [ "$n" -ge 2 ]; then exit 0; else exit 9; fi'
            else:
                outcome = "exit 11"
            body = f'''#!/bin/bash
n=$(cat "{counter}" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "{counter}"
if [ "${{{env_names[index]}:-}}" != "{env_values[index]}" ]; then exit 7; fi
{outcome}
'''
            with open(command, "w") as f:
                f.write(body)
            os.chmod(command, 0o755)
            commands.append(command)

        controlled_lines = [
            f"{names[i]},{env_names[i]}={env_values[i]},{commands[i]}"
            for i in range(3)
        ]
        with open(csv_path, "w") as f:
            f.write("\n".join(controlled_lines) + "\n")
        os.chmod(csv_path, 0o666)
        os.chown(csv_path, user.pw_uid, user.pw_gid)
        try:
            os.unlink(log_path)
        except FileNotFoundError:
            pass

        result = subprocess.run(
            ["runuser", "-u", "user", "--", "env", "HOME=/home/user",
             "python3", script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )

        assert result.returncode == 0, (
            f"The supervisor exited with code {result.returncode}. "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )
        assert os.path.isfile(log_path), "Executing the supervisor did not create supervisor.log."
        with open(log_path, "r") as f:
            actual_log = f.read().splitlines()
        expected_log = [
            f"[{names[0]}] SUCCESS",
            f"[{names[1]}] SUCCESS",
            f"[{names[2]}] FAILED",
        ]
        assert actual_log == expected_log, "The supervisor logged incorrect controlled outcomes or order."

        counts = []
        for index in range(3):
            counter = os.path.join(workdir, f"count_{index}")
            assert os.path.isfile(counter), f"Controlled command {index} was not executed."
            with open(counter, "r") as f:
                counts.append(int(f.read().strip()))
        assert counts == [1, 2, 2], (
            "Commands must run once after success and exactly twice after an initial failure."
        )
    finally:
        restore(csv_path, saved_csv)
        restore(log_path, saved_log)
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
