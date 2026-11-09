#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shlex
import shutil
import stat
import subprocess
import textwrap

import pytest

ROOT = "/home/user/polyglot"
CORE = ROOT + "/core"
WORKER_DIR = ROOT + "/worker"
COMPUTE = CORE + "/compute"
WORKER = WORKER_DIR + "/worker"
SCRIPT = ROOT + "/build_and_test.py"
RESULTS = ROOT + "/test_results.json"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 30)
    return subprocess.run(cmd, **kwargs)


def prime_sum(n):
    total = 0
    for value in range(2, n + 1):
        prime = True
        divisor = 2
        while divisor * divisor <= value:
            if value % divisor == 0:
                prime = False
                break
            divisor += 1
        if prime:
            total += value
    return total


def assert_elf(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled executable"


def test_01_required_files_and_artifacts_exist():
    assert os.path.isfile(COMPUTE), f"C binary not found at {COMPUTE}"
    assert os.access(COMPUTE, os.X_OK), f"C binary at {COMPUTE} is not executable"
    assert os.path.isfile(WORKER), f"Go binary not found at {WORKER}"
    assert os.access(WORKER, os.X_OK), f"Go binary at {WORKER} is not executable"
    assert os.path.isfile(SCRIPT), f"Python script not found at {SCRIPT}"


def test_02_python_script_really_orchestrates_builds_and_integration():
    make_path = shutil.which("make")
    go_path = shutil.which("go")
    assert make_path and go_path

    make_backup = make_path + ".__verifier_real"
    go_backup = go_path + ".__verifier_real"
    make_log = "/tmp/verifier_make.log"
    go_log = "/tmp/verifier_go.log"
    worker_input_log = "/tmp/verifier_worker_input.log"

    for path in (make_backup, go_backup, make_log, go_log, worker_input_log,
                 WORKER + ".__verifier_real"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    for path in (COMPUTE, WORKER, RESULTS):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    os.rename(make_path, make_backup)
    with open(make_path, "w") as f:
        f.write("#!/bin/sh\nprintf '%s\\t%s\\n' \"$PWD\" \"$*\" >> " + shlex.quote(make_log) + "\nexec " + shlex.quote(make_backup) + " \"$@\"\n")
    os.chmod(make_path, 0o755)

    os.rename(go_path, go_backup)
    go_wrapper = f'''#!/bin/sh
printf '%s\\t%s\\n' "$PWD" "$*" >> {shlex.quote(go_log)}
out=""
previous=""
for argument in "$@"; do
    if [ "$previous" = "-o" ]; then out="$argument"; fi
    previous="$argument"
done
{shlex.quote(go_backup)} "$@"
rc=$?
if [ "$rc" -eq 0 ] && [ "$PWD" = {shlex.quote(WORKER_DIR)} ] && [ -n "$out" ]; then
    case "$out" in
        /*) target="$out" ;;
        *) target="$PWD/$out" ;;
    esac
    if [ -f "$target" ]; then
        real="$target.__verifier_real"
        rm -f "$real"
        mv "$target" "$real"
        cat > "$target" <<WRAPPER_EOF
#!/bin/sh
input=\$(cat)
printf '%s\\n' "\$input" >> {shlex.quote(worker_input_log)}
printf '%s' "\$input" | exec "$real"
WRAPPER_EOF
        chmod +x "$target"
    fi
fi
exit "$rc"
'''
    with open(go_path, "w") as f:
        f.write(go_wrapper)
    os.chmod(go_path, 0o755)

    result = None
    try:
        result = run(["python3", SCRIPT], timeout=90)
    finally:
        try:
            os.remove(make_path)
        except FileNotFoundError:
            pass
        if os.path.lexists(make_backup):
            os.rename(make_backup, make_path)
        try:
            os.remove(go_path)
        except FileNotFoundError:
            pass
        if os.path.lexists(go_backup):
            os.rename(go_backup, go_path)
        real_worker = WORKER + ".__verifier_real"
        if os.path.isfile(real_worker):
            try:
                os.remove(WORKER)
            except FileNotFoundError:
                pass
            os.rename(real_worker, WORKER)

    assert result is not None
    assert result.returncode == 0, (
        f"Python script failed with return code {result.returncode}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )

    assert os.path.isfile(make_log), "build_and_test.py did not invoke make"
    with open(make_log) as f:
        make_calls = [line.rstrip("\n").split("\t", 1) for line in f if line.strip()]
    assert any(cwd == CORE for cwd, _ in make_calls), "make was not run in the C directory"

    assert os.path.isfile(go_log), "build_and_test.py did not invoke go"
    with open(go_log) as f:
        go_calls = [line.rstrip("\n").split("\t", 1) for line in f if line.strip()]
    valid_go_build = False
    for cwd, args_text in go_calls:
        args = shlex.split(args_text)
        if cwd == WORKER_DIR and len(args) >= 5 and args[0] == "build":
            if "-o" in args and args[args.index("-o") + 1] == "worker" and "main.go" in args:
                valid_go_build = True
    assert valid_go_build, "go build -o worker main.go was not run in the worker directory"

    assert os.path.isfile(worker_input_log), "the newly built worker was not executed"
    with open(worker_input_log) as f:
        recorded_inputs = [line.strip() for line in f if line.strip()]
    assert any(json.loads(value) == [10, 20, 30] for value in recorded_inputs), (
        "the worker was not passed [10, 20, 30] by build_and_test.py"
    )

    assert os.path.isfile(COMPUTE) and os.access(COMPUTE, os.X_OK)
    assert os.path.isfile(WORKER) and os.access(WORKER, os.X_OK)
    assert_elf(COMPUTE)
    assert_elf(WORKER)

    assert os.path.isfile(RESULTS), f"Test results JSON not found at {RESULTS}"
    with open(RESULTS) as f:
        try:
            results_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("test_results.json is not valid JSON")
    expected_results = {
        "c_build_ok": True,
        "go_build_ok": True,
        "integration_passed": True,
    }
    assert results_data == expected_results, f"Expected {expected_results}, got {results_data}"


def test_03_c_binary_fixed_and_general_behavior():
    result = run([COMPUTE, "10"])
    assert result.returncode == 0, f"C binary failed with return code {result.returncode}"
    assert result.stdout.strip() == "17", f"Expected '17', got '{result.stdout.strip()}'"

    result = run([COMPUTE, "11"])
    assert result.returncode == 0
    assert result.stdout.strip() == "28", f"Expected '28', got '{result.stdout.strip()}'"

    values = random.SystemRandom().sample(range(2, 500), 12)
    for value in values:
        result = run([COMPUTE, str(value)])
        assert result.returncode == 0, f"compute failed for N={value}: {result.stderr}"
        assert result.stdout.strip() == str(prime_sum(value)), (
            f"incorrect prime sum for N={value}: {result.stdout!r}"
        )


def test_04_go_worker_fixed_behavior():
    result = run([WORKER], input="[10, 20, 30]")
    assert result.returncode == 0, f"Go worker failed with return code {result.returncode}"
    try:
        output_json = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Go worker output is not valid JSON: {result.stdout}")
    output_normalized = {str(k): int(v) for k, v in output_json.items()}
    expected_normalized = {"10": 17, "20": 77, "30": 129}
    assert output_normalized == expected_normalized, (
        f"Expected {expected_normalized}, got {output_normalized}"
    )


def test_05_go_worker_processes_general_json_by_calling_compute():
    with open(WORKER_DIR + "/main.go") as f:
        source = f.read()
    assert '"os/exec"' in source and re.search(r"\bexec\.Command\s*\(", source), (
        "main.go must use os/exec to call the C component"
    )
    assert re.search(r"\bgo\s+(?:func\s*\(|[A-Za-z_])", source), "main.go does not start a goroutine"
    assert re.search(r"\bchan\b", source), "main.go does not use a channel"

    saved_compute = COMPUTE + ".__verifier_saved"
    call_log = "/tmp/verifier_compute_calls.log"
    try:
        os.remove(saved_compute)
    except FileNotFoundError:
        pass
    try:
        os.remove(call_log)
    except FileNotFoundError:
        pass

    os.rename(COMPUTE, saved_compute)
    shim = f'''#!/bin/sh
case "$1" in
  -|*[^0-9-]*|*-*) exit 2 ;;
esac
printf '%s\\n' "$1" >> {shlex.quote(call_log)}
printf '%s\\n' "$(( $1 * 7919 + 123 ))"
'''
    with open(COMPUTE, "w") as f:
        f.write(shim)
    os.chmod(COMPUTE, 0o755)

    numbers = random.SystemRandom().sample(range(40, 2000), 9)
    try:
        result = run([WORKER], input=json.dumps(numbers))
    finally:
        try:
            os.remove(COMPUTE)
        except FileNotFoundError:
            pass
        os.rename(saved_compute, COMPUTE)

    assert result.returncode == 0, f"worker failed on generated input: {result.stderr}"
    try:
        output = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Go worker output is not valid JSON: {result.stdout}")
    normalized = {str(k): int(v) for k, v in output.items()}
    expected = {str(n): n * 7919 + 123 for n in numbers}
    assert normalized == expected, f"Expected {expected}, got {normalized}"

    assert os.path.isfile(call_log), "worker did not execute the C compute program"
    with open(call_log) as f:
        calls = [int(line.strip()) for line in f if line.strip()]
    assert sorted(calls) == sorted(numbers), (
        f"compute was not called once for every input; expected {numbers}, got {calls}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
