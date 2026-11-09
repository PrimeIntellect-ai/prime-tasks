#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import subprocess
import sys

EXPECTED_LOG = (
    "[2023-10-27 10:01:05] Loss: 10.5\n"
    "[2023-10-27 10:02:10] Loss: 25.2\n"
    "[2023-10-27 10:03:15] Loss: 65.8\n"
    "[2023-10-27 10:04:20] Loss: 150.4\n"
    "[2023-10-27 10:05:25] Loss: 340.9\n"
)


def test_recovered_log():
    log_path = "/home/user/app/recovered.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read()

    assert "[2023-10-27 10:01:05] Loss: 10.5" in content, "Recovered log is missing expected content."
    assert "[2023-10-27 10:05:25] Loss: 340.9" in content, "Recovered log is missing expected content."
    assert content == EXPECTED_LOG, "recovered.log is not the complete deleted training log."

    # If the permitted-to-remain runner is still alive, compare against its
    # deleted open file directly rather than relying only on fixed samples.
    open_deleted_logs = []
    for proc_name in os.listdir("/proc"):
        if not proc_name.isdigit():
            continue
        proc_dir = os.path.join("/proc", proc_name)
        try:
            with open(os.path.join(proc_dir, "cmdline"), "rb") as f:
                cmdline = f.read().replace(b"\x00", b" ")
            if b"runner.py" not in cmdline:
                continue
            fd_dir = os.path.join(proc_dir, "fd")
            for fd in os.listdir(fd_dir):
                fd_path = os.path.join(fd_dir, fd)
                try:
                    target = os.readlink(fd_path)
                    if "training.log" in target and "(deleted)" in target:
                        with open(fd_path, "rb") as f:
                            open_deleted_logs.append(f.read().decode())
                except (OSError, UnicodeDecodeError):
                    pass
        except OSError:
            pass

    if open_deleted_logs:
        assert content in open_deleted_logs, "recovered.log differs from the deleted file held open by runner.py."


def test_divergence_time():
    txt_path = "/home/user/app/divergence_time.txt"
    assert os.path.isfile(txt_path), f"File {txt_path} does not exist."
    with open(txt_path, "r") as f:
        content = f.read().strip()

    assert content == "2023-10-27 10:04:20", f"Incorrect divergence time found: {content}"

    with open("/home/user/app/recovered.log", "r") as f:
        entries = []
        for line in f:
            match = re.fullmatch(r"\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] Loss: (-?\d+(?:\.\d+)?)\n?", line)
            assert match, f"Malformed recovered log line: {line!r}"
            entries.append((match.group(1), float(match.group(2))))
    derived = next(timestamp for timestamp, loss in entries if loss > 100.0)
    assert content == derived, "divergence_time.txt was not derived from the first loss strictly above 100.0."


def _is_name(node, name):
    return isinstance(node, ast.Name) and node.id == name


def _is_product(node, left, right):
    return (
        isinstance(node, ast.BinOp)
        and isinstance(node.op, ast.Mult)
        and ((_is_name(node.left, left) and _is_name(node.right, right))
             or (_is_name(node.left, right) and _is_name(node.right, left)))
    )


def test_train_script_fixed():
    train_path = "/home/user/app/train.py"
    assert os.path.isfile(train_path), f"File {train_path} does not exist."
    with open(train_path, "r") as f:
        content = f.read()

    # Retain the original source assertions.
    assert re.search(r"x\s*=\s*x\s*-\s*learning_rate\s*\*\s*grad", content) or \
           re.search(r"x\s*-=\s*learning_rate\s*\*\s*grad", content), \
           "The weight update step in train.py was not fixed to subtract the gradient."
    assert "assert loss >= 0" in content.replace("0.0", "0"), "The assertion 'assert loss >= 0.0' is missing in train.py."

    tree = ast.parse(content, filename=train_path)
    train_functions = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == "train"]
    assert len(train_functions) == 1, "train.py must define one train() function."
    train_func = train_functions[0]

    update_nodes = []
    assertion_nodes = []
    for loop in [n for n in ast.walk(train_func) if isinstance(n, (ast.For, ast.While))]:
        for node in ast.walk(loop):
            if isinstance(node, ast.Assign) and len(node.targets) == 1 and _is_name(node.targets[0], "x"):
                value = node.value
                if isinstance(value, ast.BinOp) and isinstance(value.op, ast.Sub) and _is_name(value.left, "x") and _is_product(value.right, "learning_rate", "grad"):
                    update_nodes.append(node)
            elif isinstance(node, ast.AugAssign) and _is_name(node.target, "x") and isinstance(node.op, ast.Sub) and _is_product(node.value, "learning_rate", "grad"):
                update_nodes.append(node)
            elif isinstance(node, ast.Assert):
                test = node.test
                valid_test = (
                    isinstance(test, ast.Compare)
                    and _is_name(test.left, "loss")
                    and len(test.ops) == 1
                    and isinstance(test.ops[0], ast.GtE)
                    and len(test.comparators) == 1
                    and isinstance(test.comparators[0], ast.Constant)
                    and test.comparators[0].value == 0.0
                )
                valid_message = isinstance(node.msg, ast.Constant) and node.msg.value == "Loss cannot be negative"
                if valid_test and valid_message:
                    assertion_nodes.append(node)

    assert update_nodes, "The active training loop does not subtract learning_rate * grad from x."
    assert assertion_nodes, "The required loss assertion is not present in the training loop."

    # Trace train() and require the actual update and assertion source lines to run,
    # preventing dead-code implementations from satisfying the AST checks.
    trace_code = r'''
import importlib.util, json, os, sys
path = os.path.abspath(sys.argv[1])
spec = importlib.util.spec_from_file_location("submitted_train", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
executed = set()
def tracer(frame, event, arg):
    if event == "line" and os.path.abspath(frame.f_code.co_filename) == path:
        executed.add(frame.f_lineno)
    return tracer
sys.settrace(tracer)
try:
    module.train()
finally:
    sys.settrace(None)
print("__TRACE__" + json.dumps(sorted(executed)))
'''
    traced = subprocess.run(
        [sys.executable, "-c", trace_code, train_path],
        cwd="/home/user/app", text=True, capture_output=True, timeout=10
    )
    assert traced.returncode == 0, f"Calling train() failed: {traced.stderr}"
    marker = next((line for line in reversed(traced.stdout.splitlines()) if line.startswith("__TRACE__")), None)
    assert marker is not None, "Could not collect execution trace from train()."
    executed_lines = set(json.loads(marker[len("__TRACE__"):]))
    assert executed_lines.intersection(node.lineno for node in update_nodes), "The corrected update is dead code and was not executed."
    assert executed_lines.intersection(node.lineno for node in assertion_nodes), "The required assertion is dead code and was not executed."


def test_success_txt():
    success_path = "/home/user/app/success.txt"
    assert os.path.isfile(success_path), f"File {success_path} does not exist."
    with open(success_path, "r") as f:
        content = f.read().strip()

    assert "Final x: 3.000" in content, f"success.txt does not contain the expected converged value. Found: {content}"

    result = subprocess.run(
        [sys.executable, "/home/user/app/train.py"],
        cwd="/home/user/app", text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, f"The fixed train.py failed when executed: {result.stderr}"
    match = re.fullmatch(r"Final x: (-?\d+(?:\.\d+)?)\s*", result.stdout)
    assert match, f"Unexpected train.py output: {result.stdout!r}"
    assert abs(float(match.group(1)) - 3.0) <= 0.001, "Executing train.py does not converge to x=3.0."

    with open(success_path, "r") as f:
        saved_output = f.read()
    assert saved_output == result.stdout, "success.txt is not the redirected output of the current fixed train.py."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
