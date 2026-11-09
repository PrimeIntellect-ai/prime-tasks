#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess
import sys
import textwrap
import uuid

import pytest

PROJECT_DIR = "/home/user/polyglot_project"
FIXES_PATCH = os.path.join(PROJECT_DIR, "fixes.patch")
ORCHESTRATOR_PY = os.path.join(PROJECT_DIR, "orchestrator.py")
SUCCESS_LOG = os.path.join(PROJECT_DIR, "success.log")
WORKER_BIN = os.path.join(PROJECT_DIR, "worker")
PARSER_BIN = os.path.join(PROJECT_DIR, "parser")
WORKER_SOURCE = os.path.join(PROJECT_DIR, "worker.c")
PARSER_SOURCE = os.path.join(PROJECT_DIR, "parser.rs")
E2E_TEST = os.path.join(PROJECT_DIR, "e2e_test.py")
CALL_LOG = "/tmp/orchestrator_subprocess_calls.jsonl"
E2E_MARKER = "/tmp/polyglot_e2e_ran"

ORIGINAL_WORKER = '''#include <stdio.h>
int main() {
    int arr[5] = {1, 2, 3, 4, 5};
    int sum = 0;
    // UB: accessing arr[5]
    for (int i = 0; i <= 5; i++) {
        sum += arr[i];
    }
    printf("Sum: %d\\n", sum);
    return 0;
}
'''

ORIGINAL_PARSER = '''fn main() {
    let mut s = String::from("hello");
    let r1 = &s;
    let r2 = &mut s;

    println!("Read: {}", r1);
    r2.push_str(" world");
    println!("Write: {}", r2);
}
'''

RUNNER = r'''
import json
import os
import runpy
import subprocess
import sys

log_path = sys.argv[1]
script_path = sys.argv[2]

_originals = {}
for _name in ("run", "check_call", "check_output", "call", "Popen"):
    _originals[_name] = getattr(subprocess, _name)

def _make_wrapper(name):
    original = _originals[name]
    def wrapper(*args, **kwargs):
        command = args[0] if args else kwargs.get("args")
        record = {
            "api": name,
            "command": repr(command),
            "arguments": repr(args),
            "keywords": repr(kwargs),
        }
        with open(log_path, "a", encoding="utf-8") as log:
            log.write(json.dumps(record) + "\\n")
        return original(*args, **kwargs)
    return wrapper

for _name in _originals:
    setattr(subprocess, _name, _make_wrapper(_name))

os.chdir(os.path.dirname(script_path))
sys.argv = [script_path]
runpy.run_path(script_path, run_name="__main__")
'''


def _write(path, content):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(content)


def _is_elf(path):
    if not os.path.isfile(path):
        return False
    with open(path, "rb") as f:
        return f.read(4) == b"\x7fELF"


@pytest.fixture(scope="session", autouse=True)
def exercise_submission():
    assert os.path.isfile(FIXES_PATCH), f"Patch file {FIXES_PATCH} does not exist."
    assert os.path.isfile(ORCHESTRATOR_PY), f"Orchestrator script {ORCHESTRATOR_PY} does not exist."

    with open(FIXES_PATCH, "r", encoding="utf-8", errors="replace") as f:
        patch_text = f.read()
    for filename in ("worker.c", "parser.rs"):
        escaped = re.escape(filename)
        assert re.search(r"^---\s+\S*" + escaped + r"(?:\s|$)", patch_text, re.MULTILINE), \
            f"fixes.patch has no unified-diff old-file header for {filename}"
        assert re.search(r"^\+\+\+\s+\S*" + escaped + r"(?:\s|$)", patch_text, re.MULTILINE), \
            f"fixes.patch has no unified-diff new-file header for {filename}"
        assert re.search(r"^@@\s", patch_text, re.MULTILINE), "fixes.patch contains no unified-diff hunk"

    nonce = uuid.uuid4().hex
    canonical_e2e = textwrap.dedent(f'''\
        import os
        import subprocess
        import sys

        def run_test():
            try:
                worker_out = subprocess.check_output(['./worker'], text=True).strip()
                assert worker_out == "Sum: 15", f"Worker failed: {{worker_out}}"

                parser_out = subprocess.check_output(['./parser'], text=True).strip()
                assert parser_out == "Read: hello\\nWrite: hello world", f"Parser failed: {{parser_out}}"

                print("E2E TESTS PASSED")
                print("NONCE: {nonce}")
                with open("{E2E_MARKER}", "w", encoding="utf-8") as marker:
                    marker.write("{nonce}")
            except Exception as e:
                print(f"E2E TESTS FAILED: {{e}}")
                sys.exit(1)

        if __name__ == "__main__":
            run_test()
    ''')

    # Recreate the clean starting state so the submitted patch must be reusable and
    # the submitted orchestrator must perform the requested work during verification.
    _write(WORKER_SOURCE, ORIGINAL_WORKER)
    _write(PARSER_SOURCE, ORIGINAL_PARSER)
    _write(E2E_TEST, canonical_e2e)
    os.chmod(E2E_TEST, 0o755)
    for path in (WORKER_BIN, PARSER_BIN, SUCCESS_LOG, CALL_LOG, E2E_MARKER):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    runner_path = "/tmp/run_polyglot_orchestrator.py"
    _write(runner_path, RUNNER)
    result = subprocess.run(
        [sys.executable, runner_path, CALL_LOG, ORCHESTRATOR_PY],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f"orchestrator.py failed:\n{result.stdout}"

    assert os.path.isfile(CALL_LOG), "orchestrator.py made no recorded subprocess calls"
    with open(CALL_LOG, "r", encoding="utf-8") as f:
        calls = [json.loads(line) for line in f if line.strip()]
    call_texts = [" ".join((c["command"], c["arguments"], c["keywords"])) for c in calls]

    def has_call(required):
        return any(all(token in call for token in required) for call in call_texts)

    assert has_call(("patch", "fixes.patch")), \
        "orchestrator.py did not use subprocess to apply fixes.patch with patch"
    assert has_call(("gcc", "worker.c", "worker")), \
        "orchestrator.py did not use subprocess to compile worker.c with gcc"
    assert has_call(("rustc", "parser.rs", "parser")), \
        "orchestrator.py did not use subprocess to compile parser.rs with rustc"
    assert has_call(("e2e_test.py",)), \
        "orchestrator.py did not use subprocess to execute e2e_test.py"

    with open(WORKER_SOURCE, "r", encoding="utf-8") as f:
        patched_worker = f.read()
    with open(PARSER_SOURCE, "r", encoding="utf-8") as f:
        patched_parser = f.read()
    with open(E2E_TEST, "r", encoding="utf-8") as f:
        resulting_e2e = f.read()
    assert patched_worker != ORIGINAL_WORKER, "fixes.patch did not modify worker.c"
    assert patched_parser != ORIGINAL_PARSER, "fixes.patch did not modify parser.rs"
    assert resulting_e2e == canonical_e2e, "fixes.patch or orchestrator.py modified e2e_test.py"

    assert _is_elf(WORKER_BIN), "worker is not a compiled ELF executable"
    assert _is_elf(PARSER_BIN), "parser is not a compiled ELF executable"
    assert os.access(WORKER_BIN, os.X_OK), "worker is not executable"
    assert os.access(PARSER_BIN, os.X_OK), "parser is not executable"

    assert os.path.isfile(E2E_MARKER), "e2e_test.py was not successfully executed"
    with open(E2E_MARKER, "r", encoding="utf-8") as f:
        assert f.read() == nonce

    expected_log = f"E2E TESTS PASSED\nNONCE: {nonce}\n"
    assert os.path.isfile(SUCCESS_LOG), f"Success log {SUCCESS_LOG} does not exist."
    with open(SUCCESS_LOG, "r", encoding="utf-8", newline="") as f:
        actual_log = f.read()
    assert actual_log == expected_log, \
        "success.log is not exactly the stdout produced by e2e_test.py"

    # Independently compile and execute the patched sources. Sanitizers ensure the
    # worker fix actually removes the out-of-bounds access rather than merely hiding it.
    checked_worker = "/tmp/checked_polyglot_worker"
    checked_parser = "/tmp/checked_polyglot_parser"
    subprocess.run(
        ["/usr/bin/gcc", "-fsanitize=address,undefined", "-fno-sanitize-recover=all",
         "-O0", WORKER_SOURCE, "-o", checked_worker],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60,
    )
    worker_env = os.environ.copy()
    worker_env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
    checked_worker_run = subprocess.run(
        [checked_worker], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=20, env=worker_env,
    )
    assert checked_worker_run.stdout.strip() == "Sum: 15"

    subprocess.run(
        ["/usr/bin/rustc", PARSER_SOURCE, "-o", checked_parser],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60,
    )
    checked_parser_run = subprocess.run(
        [checked_parser], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=20,
    )
    assert checked_parser_run.stdout.strip() == "Read: hello\nWrite: hello world"


def test_fixes_patch_exists():
    assert os.path.isfile(FIXES_PATCH), f"Patch file {FIXES_PATCH} does not exist."


def test_orchestrator_exists():
    assert os.path.isfile(ORCHESTRATOR_PY), f"Orchestrator script {ORCHESTRATOR_PY} does not exist."


def test_success_log_content():
    assert os.path.isfile(SUCCESS_LOG), f"Success log {SUCCESS_LOG} does not exist."
    with open(SUCCESS_LOG, 'r') as f:
        content = f.read()
    assert "E2E TESTS PASSED" in content, f"{SUCCESS_LOG} does not contain 'E2E TESTS PASSED'. Found: {content}"


def test_worker_output():
    assert os.path.isfile(WORKER_BIN), f"Worker binary {WORKER_BIN} does not exist. Orchestrator may have failed to compile it."
    try:
        output = subprocess.check_output([WORKER_BIN], text=True, timeout=20).strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Worker binary failed to run: {e}")
    assert output == "Sum: 15", f"Worker output was '{output}', expected 'Sum: 15'."


def test_parser_output():
    assert os.path.isfile(PARSER_BIN), f"Parser binary {PARSER_BIN} does not exist. Orchestrator may have failed to compile it."
    try:
        output = subprocess.check_output([PARSER_BIN], text=True, timeout=20).strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Parser binary failed to run: {e}")

    expected_output = "Read: hello\nWrite: hello world"
    assert output == expected_output, f"Parser output was '{output}', expected '{expected_output}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
