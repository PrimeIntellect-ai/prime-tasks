#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import pytest

def test_operator_executable_exists():
    operator_path = "/home/user/operator"
    assert os.path.isfile(operator_path), f"File {operator_path} does not exist."
    st = os.stat(operator_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {operator_path} is not executable."

def test_sync_manifests_script_exists_and_executable():
    script_path = "/home/user/sync_manifests.sh"
    assert os.path.isfile(script_path), f"File {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()
    assert "set -e" in content, f"{script_path} must include 'set -e'."
    assert "set -o pipefail" in content, f"{script_path} must include 'set -o pipefail'."

def test_output_yaml_content():
    yaml_path = "/home/user/manifests/output.yaml"
    assert os.path.isfile(yaml_path), f"File {yaml_path} does not exist."
    with open(yaml_path, "r") as f:
        content = f.read()
    expected_path = "upstreamSocket: /home/user/run/upstream.sock"
    assert expected_path in content, f"{yaml_path} does not contain the correct upstreamSocket path."

def test_directories_exist():
    manifests_dir = "/home/user/manifests"
    run_dir = "/home/user/run"
    assert os.path.isdir(manifests_dir), f"Directory {manifests_dir} does not exist."
    assert os.path.isdir(run_dir), f"Directory {run_dir} does not exist."

def test_sync_status_log():
    log_path = "/home/user/sync_status.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "SUCCESS", f"{log_path} does not contain exactly 'SUCCESS'."

def test_storage_cleanup_logic():
    manifests_dir = "/home/user/manifests"

    assert not os.path.exists(os.path.join(manifests_dir, "dummy3.bak")), "dummy3.bak should have been deleted."
    assert not os.path.exists(os.path.join(manifests_dir, "dummy4.bak")), "dummy4.bak should have been deleted."

    assert os.path.isfile(os.path.join(manifests_dir, "dummy1.txt")), "dummy1.txt should still exist."
    assert os.path.isfile(os.path.join(manifests_dir, "dummy2.txt")), "dummy2.txt should still exist."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_behavior.py
import os
import random
import shutil
import stat
import string
import subprocess
import tempfile

HOME = "/home/user"
SOURCE = os.path.join(HOME, "operator.cpp")
OPERATOR = os.path.join(HOME, "operator")
WRAPPER = os.path.join(HOME, "sync_manifests.sh")
INPUT = os.path.join(HOME, "input.conf")
MANIFESTS = os.path.join(HOME, "manifests")
RUN_DIR = os.path.join(HOME, "run")
OUTPUT = os.path.join(MANIFESTS, "output.yaml")
STATUS = os.path.join(HOME, "sync_status.log")

assert os.path.isfile(SOURCE), "operator.cpp is missing"
assert os.path.isfile(OPERATOR), "compiled operator is missing"
assert os.path.isfile(WRAPPER), "wrapper is missing"
assert os.access(OPERATOR, os.X_OK), "operator is not executable"
assert os.access(WRAPPER, os.X_OK), "wrapper is not executable"
with open(OPERATOR, "rb") as f:
    assert f.read(4) == b"\x7fELF", "operator must be a compiled executable"

with open(INPUT, "rb") as f:
    original_input = f.read()

alphabet = string.ascii_lowercase + string.digits
nonce = "verify" + "".join(random.SystemRandom().choice(alphabet) for _ in range(16))

def write_input(app):
    with open(INPUT, "w") as f:
        f.write(f"app_name={app}\nreplicas=3\n")

def read_output():
    with open(OUTPUT) as f:
        return f.read()

def run_operator(path, app):
    os.makedirs(MANIFESTS, exist_ok=True)
    write_input(app)
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run([path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert os.path.isfile(OUTPUT), "operator did not generate output.yaml"
    content = read_output()
    assert f"  name: {app}\n" in content, "operator did not read the dynamic app_name"
    assert "upstreamSocket: /home/user/run/upstream.sock" in content
    assert "/home/user/sockets/upstream.sock" not in content
    return content

with tempfile.TemporaryDirectory() as td:
    rebuilt = os.path.join(td, "operator-from-source")
    compile_result = subprocess.run(
        ["g++", SOURCE, "-o", rebuilt], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert compile_result.returncode == 0, "operator.cpp does not compile:\n" + compile_result.stderr.decode(errors="replace")
    source_output = run_operator(rebuilt, nonce + "src")
    installed_output = run_operator(OPERATOR, nonce + "src")
    assert installed_output == source_output, "installed operator behavior differs from the submitted C++ source"

# With exactly three files before execution, a .bak file must remain. This also
# verifies that the wrapper safely creates both required directories.
shutil.rmtree(MANIFESTS, ignore_errors=True)
shutil.rmtree(RUN_DIR, ignore_errors=True)
os.makedirs(MANIFESTS)
for name in (nonce + "-one.txt", nonce + "-two.txt", nonce + "-retain.bak"):
    open(os.path.join(MANIFESTS, name), "w").close()
write_input(nonce + "wrapper")
result = subprocess.run([WRAPPER], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
assert result.returncode == 0, result.stderr.decode(errors="replace")
assert os.path.isdir(RUN_DIR), "wrapper did not create /home/user/run"
assert os.path.exists(os.path.join(MANIFESTS, nonce + "-retain.bak")), ".bak was deleted when the pre-run file count was exactly 3"
assert f"  name: {nonce}wrapper\n" in read_output()
with open(STATUS) as f:
    assert f.read().strip() == "SUCCESS"

# output.yaml makes the next pre-run count greater than three. All .bak files
# must now be removed, while ordinary files remain.
extra_bak = os.path.join(MANIFESTS, nonce + "-extra.bak")
open(extra_bak, "w").close()
result = subprocess.run([WRAPPER], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
assert result.returncode == 0, result.stderr.decode(errors="replace")
assert not os.path.exists(os.path.join(MANIFESTS, nonce + "-retain.bak"))
assert not os.path.exists(extra_bak)
assert os.path.isfile(os.path.join(MANIFESTS, nonce + "-one.txt"))
assert os.path.isfile(os.path.join(MANIFESTS, nonce + "-two.txt"))

# Replace the operator temporarily with a compiled failing program that leaves
# a marker. The wrapper must actually invoke it, record FAILURE, and return 1.
with tempfile.TemporaryDirectory() as td:
    backup = os.path.join(td, "real-operator")
    failing_cpp = os.path.join(td, "failing.cpp")
    failing_bin = os.path.join(td, "failing-operator")
    marker = os.path.join(td, "invoked")
    shutil.copy2(OPERATOR, backup)
    with open(failing_cpp, "w") as f:
        f.write('#include <fstream>\nint main(){std::ofstream("' + marker + '") << "yes"; return 23;}\n')
    result = subprocess.run(["g++", failing_cpp, "-o", failing_bin], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    try:
        shutil.copy2(failing_bin, OPERATOR)
        os.chmod(OPERATOR, os.stat(OPERATOR).st_mode | stat.S_IXUSR)
        result = subprocess.run([WRAPPER], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert os.path.isfile(marker), "wrapper did not execute /home/user/operator"
        assert result.returncode == 1, "wrapper must exit with code 1 when the operator fails"
        with open(STATUS) as f:
            assert f.read().strip() == "FAILURE", "wrapper did not record FAILURE"
    finally:
        shutil.copy2(backup, OPERATOR)

# Restore the supplied input and leave the required successful final state.
with open(INPUT, "wb") as f:
    f.write(original_input)
shutil.rmtree(MANIFESTS, ignore_errors=True)
os.makedirs(MANIFESTS)
for name in ("dummy1.txt", "dummy2.txt", "dummy3.bak", "dummy4.bak"):
    open(os.path.join(MANIFESTS, name), "w").close()
result = subprocess.run([WRAPPER], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
assert result.returncode == 0, result.stderr.decode(errors="replace")
assert os.path.isfile(OUTPUT)
assert not os.path.exists(os.path.join(MANIFESTS, "dummy3.bak"))
assert not os.path.exists(os.path.join(MANIFESTS, "dummy4.bak"))
assert os.path.isfile(os.path.join(MANIFESTS, "dummy1.txt"))
assert os.path.isfile(os.path.join(MANIFESTS, "dummy2.txt"))
with open(STATUS) as f:
    assert f.read().strip() == "SUCCESS"
DYNAMIC_EOF

passed=1
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || passed=0
if [ "$passed" -eq 1 ]; then
    python3 /tmp/test_dynamic_behavior.py 2>&1 || passed=0
fi

if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
