#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import subprocess
import uuid
from contextlib import contextmanager

OPERATOR = "/home/user/operator.py"
MANIFEST_DIR = "/home/user/manifests"
DATA_DIR = "/home/user/data"
LAUNCHER = "/home/user/launcher.sh"
START_ORDER = "/home/user/start_order.txt"
LOG = "/home/user/operator.log"


@contextmanager
def isolated_workspace():
    token = uuid.uuid4().hex
    backups = []
    saved_files = {}
    directories = [MANIFEST_DIR, DATA_DIR]
    artifacts = [LAUNCHER, START_ORDER, LOG]

    try:
        for path in artifacts:
            if os.path.exists(path):
                with open(path, "rb") as f:
                    saved_files[path] = (f.read(), os.stat(path).st_mode & 0o777)
            else:
                saved_files[path] = None

        for path in directories:
            backup = f"{path}.verifier-{token}"
            if os.path.exists(path):
                os.rename(path, backup)
                backups.append((path, backup))
            os.makedirs(path)

        for path in artifacts:
            if os.path.exists(path):
                os.remove(path)
        yield
    finally:
        for path in directories:
            if os.path.isdir(path):
                shutil.rmtree(path)
            elif os.path.exists(path):
                os.remove(path)

        for path, backup in reversed(backups):
            os.rename(backup, path)

        for path, saved in saved_files.items():
            if os.path.exists(path):
                os.remove(path)
            if saved is not None:
                content, mode = saved
                with open(path, "wb") as f:
                    f.write(content)
                os.chmod(path, mode)


def test_webhook_manifest():
    path = "/home/user/manifests/webhook.json"
    assert os.path.isfile(path), f"Webhook manifest {path} is missing."
    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Webhook manifest {path} is not valid JSON."

    assert data.get("name") == "webhook", "Webhook name incorrect in manifest."
    assert data.get("command") == "python3 -m http.server 8080 --directory /home/user/public", "Webhook command incorrect in manifest."
    assert data.get("depends_on") == ["backend"], "Webhook dependencies incorrect in manifest."


def test_start_order():
    path = "/home/user/start_order.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did you run the generated launcher?"
    with open(path, "r") as f:
        content = f.read()

    lines = [line.strip() for line in content.split('\n') if line.strip()]

    def find_index_of_service(service_name):
        for i, line in enumerate(lines):
            if service_name in line.split():
                return i
        return -1

    db_idx = find_index_of_service("db")
    backend_idx = find_index_of_service("backend")
    frontend_idx = find_index_of_service("frontend")
    webhook_idx = find_index_of_service("webhook")

    assert db_idx != -1, "Service 'db' was not found in start_order.txt"
    assert backend_idx != -1, "Service 'backend' was not found in start_order.txt"
    assert frontend_idx != -1, "Service 'frontend' was not found in start_order.txt"
    assert webhook_idx != -1, "Service 'webhook' was not found in start_order.txt"

    assert db_idx < backend_idx, "Dependency ordering failed: 'db' must start before 'backend'"
    assert backend_idx < frontend_idx, "Dependency ordering failed: 'backend' must start before 'frontend'"
    assert backend_idx < webhook_idx, "Dependency ordering failed: 'backend' must start before 'webhook'"


def test_storage_quota():
    data_dir = "/home/user/data"
    test_file = os.path.join(data_dir, "test_huge.dat")
    log_path = "/home/user/operator.log"

    try:
        with open(test_file, "wb") as f:
            f.write(b"0" * 1025000)

        if os.path.exists(log_path):
            os.remove(log_path)

        result = subprocess.run(["python3", "/home/user/operator.py"], capture_output=True)
        assert result.returncode == 2, f"Expected exit code 2 when storage quota is exceeded, got {result.returncode}"

        assert os.path.isfile(log_path), f"Log file {log_path} missing after quota exceeded."
        with open(log_path, "r") as f:
            log_content = f.read().strip()
        assert "STORAGE_QUOTA_EXCEEDED" in log_content.split('\n'), f"Log file did not contain exactly 'STORAGE_QUOTA_EXCEEDED'. Got: {log_content}"
    finally:
        if os.path.exists(test_file):
            os.remove(test_file)


def test_circular_dependency():
    manifests_dir = "/home/user/manifests"
    bad1 = os.path.join(manifests_dir, "bad1.json")
    bad2 = os.path.join(manifests_dir, "bad2.json")
    log_path = "/home/user/operator.log"

    try:
        with open(bad1, "w") as f:
            json.dump({"name": "bad1", "command": "sleep 1", "depends_on": ["bad2"]}, f)
        with open(bad2, "w") as f:
            json.dump({"name": "bad2", "command": "sleep 1", "depends_on": ["bad1"]}, f)

        if os.path.exists(log_path):
            os.remove(log_path)

        result = subprocess.run(["python3", "/home/user/operator.py"], capture_output=True)
        assert result.returncode == 1, f"Expected exit code 1 for circular dependency, got {result.returncode}"

        assert os.path.isfile(log_path), f"Log file {log_path} missing after circular dependency."
        with open(log_path, "r") as f:
            log_content = f.read().strip()
        assert "CIRCULAR_DEPENDENCY" in log_content.split('\n'), f"Log file did not contain exactly 'CIRCULAR_DEPENDENCY'. Got: {log_content}"
    finally:
        if os.path.exists(bad1):
            os.remove(bad1)
        if os.path.exists(bad2):
            os.remove(bad2)


def test_operator_generates_and_runs_random_dependency_graph():
    assert os.path.isfile(OPERATOR), "operator.py is missing"
    assert os.access(OPERATOR, os.X_OK), "operator.py is not executable"

    with isolated_workspace():
        suffix = uuid.uuid4().hex[:10]
        names = [f"svc_{suffix}_{i}" for i in range(5)]
        marker = f"/tmp/operator-marker-{uuid.uuid4().hex}"
        dependencies = {
            names[0]: [],
            names[1]: [names[0]],
            names[2]: [names[0]],
            names[3]: [names[1], names[2]],
            names[4]: [names[3]],
        }
        commands = {
            name: f"printf '%s\\n' {name} >> {marker}"
            for name in names
        }

        entries = list(names)
        random.SystemRandom().shuffle(entries)
        for name in entries:
            filename = f"manifest-{uuid.uuid4().hex}.json"
            with open(os.path.join(MANIFEST_DIR, filename), "w") as f:
                json.dump({
                    "name": name,
                    "command": commands[name],
                    "depends_on": dependencies[name],
                }, f)

        try:
            result = subprocess.run([OPERATOR], capture_output=True, text=True, timeout=15)
            assert result.returncode == 0, result.stderr or result.stdout
            assert os.path.isfile(LAUNCHER), "operator did not generate launcher.sh"
            assert os.access(LAUNCHER, os.X_OK), "generated launcher.sh is not executable"

            with open(LAUNCHER) as f:
                launcher_lines = f.read().splitlines()
            assert launcher_lines and launcher_lines[0] == "#!/bin/bash", "launcher must begin with #!/bin/bash"

            command_positions = {}
            for name in names:
                expected_command = commands[name] + " &"
                matches = [i for i, line in enumerate(launcher_lines) if line.strip() == expected_command]
                assert len(matches) == 1, f"launcher must execute {name}'s exact command once in the background"
                pos = matches[0]
                command_positions[name] = pos
                assert pos > 0, f"missing echo before {name}"
                echo_line = launcher_lines[pos - 1].strip()
                assert re.match(r"^echo(?:\s|$)", echo_line), f"line immediately before {name} is not echo"
                assert name in echo_line.split(), f"echo immediately before command does not name {name}"
                assert re.search(r">>\s*/home/user/start_order\.txt\s*$", echo_line), "echo must append to start_order.txt"
                assert pos + 1 < len(launcher_lines) and launcher_lines[pos + 1].strip() == "sleep 1", f"missing sleep 1 after {name}"

            for name, deps in dependencies.items():
                for dep in deps:
                    assert command_positions[dep] < command_positions[name], f"{dep} must precede {name}"

            if os.path.exists(START_ORDER):
                os.remove(START_ORDER)
            run = subprocess.run([LAUNCHER], capture_output=True, text=True, timeout=15)
            assert run.returncode == 0, run.stderr or run.stdout
            assert os.path.isfile(START_ORDER), "running launcher did not create start_order.txt"

            with open(START_ORDER) as f:
                start_lines = [line.strip() for line in f if line.strip()]
            found_order = []
            for line in start_lines:
                matches = [name for name in names if name in line.split()]
                assert len(matches) <= 1
                if matches:
                    found_order.append(matches[0])
            assert sorted(found_order) == sorted(names), "each generated service must be logged exactly once"
            positions = {name: found_order.index(name) for name in names}
            for name, deps in dependencies.items():
                for dep in deps:
                    assert positions[dep] < positions[name], f"runtime start order violates {dep} -> {name}"

            with open(marker) as f:
                executed = [line.strip() for line in f if line.strip()]
            assert sorted(executed) == sorted(names), "launcher did not execute every manifest command"
        finally:
            if os.path.exists(marker):
                os.remove(marker)


def test_randomized_recursive_quota_boundary_and_early_exit():
    with isolated_workspace():
        service_name = f"quota_{uuid.uuid4().hex}"
        manifest_path = os.path.join(MANIFEST_DIR, f"{uuid.uuid4().hex}.json")
        with open(manifest_path, "w") as f:
            json.dump({"name": service_name, "command": "true", "depends_on": []}, f)

        nested = os.path.join(DATA_DIR, uuid.uuid4().hex, uuid.uuid4().hex)
        os.makedirs(nested)
        split = random.SystemRandom().randint(100000, 900000)
        with open(os.path.join(DATA_DIR, uuid.uuid4().hex), "wb") as f:
            f.write(b"a" * split)
        with open(os.path.join(nested, uuid.uuid4().hex), "wb") as f:
            f.write(b"b" * (1024000 - split))

        at_limit = subprocess.run([OPERATOR], capture_output=True, text=True, timeout=15)
        assert at_limit.returncode == 0, "exactly 1024000 bytes must not exceed the quota"
        assert os.path.isfile(LAUNCHER), "operator failed to generate launcher at the quota boundary"

        with open(os.path.join(nested, uuid.uuid4().hex), "wb") as f:
            f.write(b"x")
        with open(manifest_path, "w") as f:
            f.write("this is deliberately invalid JSON")
        os.remove(LAUNCHER)
        if os.path.exists(LOG):
            os.remove(LOG)

        over_limit = subprocess.run([OPERATOR], capture_output=True, text=True, timeout=15)
        assert over_limit.returncode == 2, f"expected quota exit code 2, got {over_limit.returncode}"
        assert not os.path.exists(LAUNCHER), "operator generated launcher.sh after quota was exceeded"
        assert os.path.isfile(LOG), "quota failure did not create operator.log"
        with open(LOG) as f:
            assert f.read() == "STORAGE_QUOTA_EXCEEDED", "quota log must contain exactly STORAGE_QUOTA_EXCEEDED"


def test_randomized_circular_dependency():
    with isolated_workspace():
        names = [f"cycle_{uuid.uuid4().hex}" for _ in range(3)]
        for i, name in enumerate(names):
            with open(os.path.join(MANIFEST_DIR, f"{uuid.uuid4().hex}.json"), "w") as f:
                json.dump({
                    "name": name,
                    "command": "true",
                    "depends_on": [names[(i + 1) % len(names)]],
                }, f)

        result = subprocess.run([OPERATOR], capture_output=True, text=True, timeout=15)
        assert result.returncode == 1, f"expected circular-dependency exit code 1, got {result.returncode}"
        assert os.path.isfile(LOG), "circular dependency did not create operator.log"
        with open(LOG) as f:
            assert f.read().strip() == "CIRCULAR_DEPENDENCY", "incorrect circular-dependency log"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
