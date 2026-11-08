#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile
import uuid

CSV_PATH = "/home/user/violations.csv"
TTL_PATH = "/home/user/corporate_graph.ttl"
NAMESPACE = "http://example.org/audit/"

ORIGINAL_TTL = """@prefix ex: <http://example.org/audit/> .

ex:ShellA ex:owns ex:ShellB .
ex:ShellB ex:owns ex:ShellC .
ex:ShellC ex:transactsWith ex:ShellA .

ex:LegitA ex:owns ex:LegitB .
ex:LegitB ex:owns ex:LegitC .
ex:LegitC ex:transactsWith ex:LegitD .

ex:FraudX ex:owns ex:FraudY .
ex:FraudY ex:owns ex:FraudZ .
ex:FraudZ ex:transactsWith ex:FraudX .

ex:Loop1 ex:transactsWith ex:Loop2 .
ex:Loop2 ex:transactsWith ex:Loop3 .
ex:Loop3 ex:transactsWith ex:Loop1 ."""

ORIGINAL_CSV = "FraudX,FraudY,FraudZ\nShellA,ShellB,ShellC"


def discover_python_scripts():
    candidates = []
    excluded = {"/proc", "/sys", "/dev", "/tests", "/logs"}
    verifier_path = os.path.realpath(__file__)

    for root, dirs, files in os.walk("/", topdown=True, followlinks=False):
        dirs[:] = [
            d for d in dirs
            if os.path.join(root, d) not in excluded and d != "__pycache__"
        ]
        if any(root == path or root.startswith(path + os.sep) for path in excluded):
            dirs[:] = []
            continue

        for name in files:
            path = os.path.join(root, name)
            if os.path.realpath(path) == verifier_path:
                continue
            try:
                info = os.stat(path)
                if not stat.S_ISREG(info.st_mode) or info.st_size > 2_000_000:
                    continue
                with open(path, "rb") as handle:
                    data = handle.read()
            except (OSError, PermissionError):
                continue

            if b"rdflib" not in data:
                continue
            first_line = data.splitlines()[0] if data.splitlines() else b""
            looks_python = (
                name.endswith(".py")
                or (first_line.startswith(b"#!") and b"python" in first_line.lower())
                or (b"corporate_graph.ttl" in data and b"violations.csv" in data)
            )
            if looks_python:
                candidates.append(path)

    return sorted(set(candidates))


def make_turtle(triples):
    lines = ["@prefix ex: <http://example.org/audit/> .", ""]
    lines.extend(f"ex:{s} ex:{p} ex:{o} ." for s, p, o in triples)
    return "\n".join(lines) + "\n"


def run_candidate(script, turtle, expected_rows, helper_dir, query_log):
    with open(TTL_PATH, "w") as handle:
        handle.write(turtle)
    try:
        os.remove(CSV_PATH)
    except FileNotFoundError:
        pass
    try:
        os.remove(query_log)
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env["RDFLIB_QUERY_LOG"] = query_log
    env["PYTHONPATH"] = helper_dir + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )

    result = subprocess.run(
        ["python3", script],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    if result.returncode != 0:
        return False, f"exit {result.returncode}: {result.stderr[-500:]}"
    if not os.path.isfile(query_log) or os.path.getsize(query_log) == 0:
        return False, "no rdflib Graph.query call was observed"
    if not os.path.isfile(CSV_PATH):
        return False, "violations.csv was not generated"

    with open(CSV_PATH, "r") as handle:
        actual = handle.read().strip()
    expected = "\n".join(",".join(row) for row in sorted(expected_rows))
    if actual != expected:
        return False, f"expected {expected!r}, got {actual!r}"
    return True, ""


def test_final_state_and_script_behavior():
    # Preserve the original verifier's assertions about the submitted final state.
    assert os.path.exists(CSV_PATH), f"Expected output file {CSV_PATH} is missing."
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} is not a file."
    with open(CSV_PATH, "r") as handle:
        assert handle.read().strip() == ORIGINAL_CSV

    assert os.path.exists(TTL_PATH), f"Original file {TTL_PATH} is missing."
    with open(TTL_PATH, "r") as handle:
        assert handle.read().strip() == ORIGINAL_TTL.strip(), \
            f"Original file {TTL_PATH} was modified."

    candidates = discover_python_scripts()
    assert candidates, "No Python script using rdflib was found."

    nonce = uuid.uuid4().hex[:10]
    a1, b1, c1 = f"Alpha{nonce}", f"Beta{nonce}", f"Gamma{nonce}"
    a2, b2, c2 = f"Delta{nonce}", f"Epsilon{nonce}", f"Zeta{nonce}"
    bad_a, bad_b, bad_c, other = (
        f"NoMatchA{nonce}", f"NoMatchB{nonce}",
        f"NoMatchC{nonce}", f"Other{nonce}"
    )

    cases = [
        (
            make_turtle([
                (a1, "owns", b1), (b1, "owns", c1),
                (c1, "transactsWith", a1),
                (a2, "owns", b2), (b2, "owns", c2),
                (c2, "transactsWith", a2),
                (bad_a, "owns", bad_b), (bad_b, "owns", bad_c),
                (bad_c, "transactsWith", other),
                (other, "transactsWith", bad_a),
            ]),
            [(a1, b1, c1), (a2, b2, c2)],
        ),
        (
            make_turtle([
                (a1, "owns", b1),
                (b1, "owns", c1), (b1, "owns", c2),
                (c1, "transactsWith", a1),
                (c2, "transactsWith", a1),
                (a2, "owns", b2), (b2, "owns", bad_c),
                (bad_c, "transactsWith", other),
                (a1, "transactsWith", c1),
            ]),
            [(a1, b1, c1), (a1, b1, c2)],
        ),
    ]

    original_ttl_bytes = open(TTL_PATH, "rb").read()
    original_csv_bytes = open(CSV_PATH, "rb").read()
    failures = []

    try:
        with tempfile.TemporaryDirectory(prefix="verifier_rdflib_") as helper_dir:
            query_log = os.path.join(helper_dir, "query.log")
            sitecustomize = '''import os\nimport rdflib\n_original_query = rdflib.Graph.query\ndef _logged_query(self, *args, **kwargs):\n    path = os.environ.get("RDFLIB_QUERY_LOG")\n    if path:\n        with open(path, "a") as log:\n            log.write("query\\n")\n    return _original_query(self, *args, **kwargs)\nrdflib.Graph.query = _logged_query\n'''
            with open(os.path.join(helper_dir, "sitecustomize.py"), "w") as handle:
                handle.write(sitecustomize)

            for script in candidates:
                passed = True
                reasons = []
                for turtle, expected in cases:
                    try:
                        ok, reason = run_candidate(
                            script, turtle, expected, helper_dir, query_log
                        )
                    except subprocess.TimeoutExpired:
                        ok, reason = False, "timed out"
                    except Exception as exc:
                        ok, reason = False, repr(exc)
                    if not ok:
                        passed = False
                        reasons.append(reason)
                        break
                if passed:
                    return
                failures.append(f"{script}: {'; '.join(reasons)}")
    finally:
        with open(TTL_PATH, "wb") as handle:
            handle.write(original_ttl_bytes)
        with open(CSV_PATH, "wb") as handle:
            handle.write(original_csv_bytes)

    assert False, "No submitted script passed behavioral SPARQL tests:\n" + "\n".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
