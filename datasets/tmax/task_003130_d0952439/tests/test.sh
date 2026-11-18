#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import heapq
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile

import pytest

QA_DIR = "/home/user/qa_env"
EXE = os.path.join(QA_DIR, "eval_graph")
SOURCE = os.path.join(QA_DIR, "eval_graph.c")
PROP = os.path.join(QA_DIR, "prop_test.sh")
PROD = os.path.join(QA_DIR, "prod_graph.txt")
REPORT = "/home/user/qa_report.txt"


def expression_value(expr):
    assert re.fullmatch(r"[0-9](?:[+*][0-9])*", expr)
    return sum(
        __import__("functools").reduce(lambda a, b: a * b, map(int, term.split("*")), 1)
        for term in expr.split("+")
    )


def run_program(path, input_data):
    process = subprocess.run(
        [path], input=input_data, text=True, capture_output=True, timeout=10
    )
    assert process.returncode == 0, (
        f"{path} returned {process.returncode}. stderr: {process.stderr}"
    )
    output = process.stdout.strip()
    assert re.fullmatch(r"-?[0-9]+", output), f"Non-integer output: {output!r}"
    return int(output)


def shortest_path_from_graph(text):
    graph = collections.defaultdict(list)
    nodes = {"START", "END"}
    for line in text.splitlines():
        if not line.strip():
            continue
        src, dst, expr = line.split()
        nodes.update((src, dst))
        graph[src].append((dst, expression_value(expr)))

    distance = {node: float("inf") for node in nodes}
    distance["START"] = 0
    queue = [(0, "START")]
    while queue:
        cost, node = heapq.heappop(queue)
        if cost != distance[node]:
            continue
        for nxt, weight in graph[node]:
            candidate = cost + weight
            if candidate < distance[nxt]:
                distance[nxt] = candidate
                heapq.heappush(queue, (candidate, nxt))
    return int(distance["END"])


def parser_corpus():
    corpus = [
        "2+3*4", "2*3+4", "9+8*7+6", "9*8+7*6", "1+2+3*4*5",
        "8*0+7", "0+9*9", "3*4*5+6*7+8", "9+9+9*9", "7*6*5*4",
        "1", "0", "4+5", "4*5", "1*2+3*4+5*6", "9*0+8*0+7",
    ]
    # A broad deterministic set whose answers are independently derived.
    for a in range(10):
        for b in range(10):
            c = (a * 7 + b * 3 + 1) % 10
            corpus.append(f"{a}+{b}*{c}")
            corpus.append(f"{a}*{b}+{c}")
    return corpus


def assert_parser(path):
    for expr in parser_corpus():
        actual = run_program(path, f"START END {expr}\n")
        assert actual == expression_value(expr), (
            f"Wrong value for {expr}: expected {expression_value(expr)}, got {actual}"
        )


def test_eval_graph_compiled_and_executable():
    assert os.path.isfile(EXE), f"File {EXE} does not exist. Did you compile the C program?"
    assert os.access(EXE, os.X_OK), f"File {EXE} is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "eval_graph must be a compiled ELF executable."


def test_eval_graph_correct_precedence():
    assert os.path.isfile(EXE), f"File {EXE} does not exist."
    process = subprocess.run(
        [EXE], input="START END 2+3*4\n", text=True, capture_output=True, timeout=10
    )
    assert process.returncode == 0, "eval_graph crashed or returned non-zero exit code."
    assert process.stdout.strip() == "14", (
        f"Expected eval_graph to output 14 for 2+3*4, but got {process.stdout.strip()}."
    )
    assert_parser(EXE)


def test_fixed_source_compiles_and_implements_precedence():
    assert os.path.isfile(SOURCE), f"File {SOURCE} does not exist."
    built = "/tmp/eval_graph_from_submitted_source"
    process = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", built],
        text=True, capture_output=True, timeout=30
    )
    assert process.returncode == 0, f"Submitted C source does not compile:\n{process.stderr}"
    assert_parser(built)


def test_graph_algorithm_on_derived_cases():
    graphs = [
        """START A 2+3*4
START B 9
A END 2*3
B END 8+8
""",
        """START A 1+2*3
START B 4*2+1
A C 2+2*2
B C 1+1*1
C END 3*3+2
A END 5*5+5
""",
        """START X 9*2
START Y 3+4
Y Z 2*3+1
Z END 8
X END 1+1
Y END 9*3
""",
        """START A 1
A B 2+3*4
B END 4
START C 8*3
C END 1
A END 9*9
""",
    ]
    for graph in graphs:
        expected = shortest_path_from_graph(graph)
        assert run_program(EXE, graph) == expected


def install_eval_wrapper(log_path, backup_path, wrong=False):
    body = f'''#!/usr/bin/python3
import json, subprocess, sys
payload = sys.stdin.read()
with open({log_path!r}, "a") as log:
    log.write(json.dumps(payload) + "\\n")
'''
    if wrong:
        body += 'sys.stdout.write("99999991\\n")\nsys.exit(0)\n'
    else:
        body += f'''p = subprocess.run([{backup_path!r}] + sys.argv[1:], input=payload, text=True, capture_output=True)
sys.stdout.write(p.stdout)
sys.stderr.write(p.stderr)
sys.exit(p.returncode)
'''
    with open(EXE, "w") as f:
        f.write(body)
    os.chmod(EXE, 0o755)


def validate_property_run(eval_log, bc_log):
    with open(eval_log) as f:
        invocations = [json.loads(line) for line in f if line.strip()]
    assert len(invocations) >= 50, (
        f"prop_test.sh exercised eval_graph only {len(invocations)} times; at least 50 are required."
    )

    expressions = []
    for payload in invocations:
        match = re.fullmatch(
            r"\s*START\s+END\s+([0-9](?:[+*][0-9])*)\s*", payload
        )
        assert match, (
            "Each generated case must be fed as a single-edge 'START END <expr>' graph; "
            f"got {payload!r}"
        )
        expressions.append(match.group(1))

    assert os.path.exists(bc_log), "prop_test.sh did not invoke the system bc command."
    bc_text = ""
    with open(bc_log) as f:
        for line in f:
            record = json.loads(line)
            bc_text += "\n" + record.get("stdin", "")
            bc_text += "\n" + "\n".join(record.get("files", []))

    used_by_bc = collections.Counter(
        re.findall(r"(?<![0-9+*])[0-9](?:[+*][0-9])*(?![0-9+*])", bc_text)
    )
    generated = collections.Counter(expressions)
    missing = generated - used_by_bc
    assert not missing, (
        "Not all generated expressions were supplied to bc for their expected values; "
        f"missing examples: {list(missing.elements())[:5]}"
    )
    return expressions


def test_prop_test_sh_exists_and_passes():
    assert os.path.isfile(PROP), f"File {PROP} does not exist."
    assert os.access(PROP, os.X_OK), f"File {PROP} is not executable."

    work = tempfile.mkdtemp(prefix="prop_verify_")
    eval_backup = os.path.join(work, "eval_graph.real")
    bc_path = shutil.which("bc")
    assert bc_path, "System bc command is unavailable."
    bc_path = os.path.realpath(bc_path)
    bc_backup = os.path.join(work, "bc.real")
    eval_log = os.path.join(work, "eval.log")
    bc_log = os.path.join(work, "bc.log")

    os.rename(EXE, eval_backup)
    os.rename(bc_path, bc_backup)
    try:
        bc_wrapper = f'''#!/usr/bin/python3
import json, os, subprocess, sys
payload = sys.stdin.read()
files = []
for arg in sys.argv[1:]:
    if os.path.isfile(arg):
        try:
            with open(arg) as f: files.append(f.read())
        except Exception:
            pass
with open({bc_log!r}, "a") as log:
    log.write(json.dumps({{"stdin": payload, "files": files}}) + "\\n")
p = subprocess.run([{bc_backup!r}] + sys.argv[1:], input=payload, text=True, capture_output=True)
sys.stdout.write(p.stdout)
sys.stderr.write(p.stderr)
sys.exit(p.returncode)
'''
        with open(bc_path, "w") as f:
            f.write(bc_wrapper)
        os.chmod(bc_path, 0o755)

        runs = []
        for run_number in range(2):
            for path in (eval_log, bc_log):
                if os.path.exists(path):
                    os.unlink(path)
            install_eval_wrapper(eval_log, eval_backup, wrong=False)
            process = subprocess.run(
                [PROP], cwd=QA_DIR, text=True, capture_output=True, timeout=120
            )
            assert process.returncode == 0, (
                f"prop_test.sh failed or returned non-zero exit code.\n"
                f"Stdout: {process.stdout}\nStderr: {process.stderr}"
            )
            runs.append(validate_property_run(eval_log, bc_log))

        assert runs[0] != runs[1], (
            "The two property-test runs generated exactly the same cases; cases must be random."
        )

        # A real comparison test must reject an evaluator that deliberately returns bad answers.
        for path in (eval_log, bc_log):
            if os.path.exists(path):
                os.unlink(path)
        install_eval_wrapper(eval_log, eval_backup, wrong=True)
        bad = subprocess.run(
            [PROP], cwd=QA_DIR, text=True, capture_output=True, timeout=120
        )
        assert bad.returncode != 0, (
            "prop_test.sh reported success even when eval_graph returned deliberately wrong values."
        )
    finally:
        if os.path.exists(EXE):
            os.unlink(EXE)
        os.rename(eval_backup, EXE)
        if os.path.exists(bc_path):
            os.unlink(bc_path)
        os.rename(bc_backup, bc_path)
        shutil.rmtree(work, ignore_errors=True)


def test_qa_report_content():
    assert os.path.isfile(REPORT), f"File {REPORT} does not exist."
    with open(REPORT) as f:
        content = f.read().strip()
    assert content == "22", f"Expected qa_report.txt to contain '22', but got '{content}'."

    with open(PROD) as f:
        prod_text = f.read()
    expected = shortest_path_from_graph(prod_text)
    assert expected == 22
    actual = run_program(EXE, prod_text)
    assert actual == expected, "eval_graph gives the wrong result for prod_graph.txt."
    assert int(content) == actual, "qa_report.txt does not match the program's production result."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
