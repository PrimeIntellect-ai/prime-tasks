#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import random
import shutil
import stat
import string
import subprocess
import tempfile
import textwrap
import time

import pytest


def test_compiled_binaries_exist():
    tester_amd64 = "/home/user/bin/tester_amd64"
    tester_arm64 = "/home/user/bin/tester_arm64"
    tester_go = "/home/user/tester/tester.go"

    assert os.path.isfile(tester_go), f"Missing Go source file: {tester_go}"
    assert os.path.isfile(tester_amd64), f"Missing compiled binary: {tester_amd64}"
    assert os.path.isfile(tester_arm64), f"Missing compiled binary: {tester_arm64}"

    # Check executable permissions
    assert os.access(tester_amd64, os.X_OK), f"{tester_amd64} is not executable"
    assert os.access(tester_arm64, os.X_OK), f"{tester_arm64} is not executable"

    # Ensure these are real Go executables for the requested architectures.
    for path, expected_machine in ((tester_amd64, 62), (tester_arm64, 183)):
        with open(path, "rb") as f:
            header = f.read(20)
        assert len(header) >= 20 and header[:4] == b"\x7fELF", f"{path} is not an ELF executable"
        assert header[4] == 2, f"{path} is not a 64-bit ELF executable"
        endian = "little" if header[5] == 1 else "big"
        machine = int.from_bytes(header[18:20], endian)
        assert machine == expected_machine, f"{path} has wrong architecture (ELF machine {machine})"
        result = subprocess.run(["go", "version", path], capture_output=True, text=True)
        assert result.returncode == 0, f"{path} is not recognized as a Go executable: {result.stderr}"


def _check_go_concurrency_syntax(source):
    checker = r'''
package main
import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)
func main() {
    if len(os.Args) != 2 { os.Exit(2) }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(2) }
    hasGo, hasChan, hasChanOp := false, false, false
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            hasGo = true
        case *ast.ChanType:
            hasChan = true
        case *ast.SendStmt:
            hasChanOp = true
        case *ast.UnaryExpr:
            if x.Op == token.ARROW { hasChanOp = true }
        }
        return true
    })
    if !hasGo || !hasChan || !hasChanOp {
        fmt.Fprintf(os.Stderr, "goroutine=%v channel=%v channel_operation=%v\n", hasGo, hasChan, hasChanOp)
        os.Exit(1)
    }
}
'''
    with tempfile.TemporaryDirectory() as td:
        checker_path = os.path.join(td, "check.go")
        with open(checker_path, "w") as f:
            f.write(checker)
        result = subprocess.run(
            ["go", "run", checker_path, source], capture_output=True, text=True, timeout=60
        )
        assert result.returncode == 0, (
            "tester.go must genuinely contain a goroutine and channel operations: "
            + result.stderr
        )


def _write_probe(path, side):
    program = textwrap.dedent(f'''\
        #!/usr/bin/env python3
        import hashlib
        import json
        import os
        import sys
        import time

        side = {side!r}
        value = sys.argv[1] if len(sys.argv) > 1 else ""
        record = json.dumps({{"side": side, "value": value, "time": time.time()}}) + "\\n"
        fd = os.open("/tmp/harness_probe.log", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
        os.write(fd, record.encode())
        os.close(fd)

        mode = "normal"
        try:
            with open("/tmp/harness_probe_mode") as f:
                mode = f.read().strip()
        except FileNotFoundError:
            pass

        if mode == "normal":
            os.makedirs("/tmp/harness_probe_coord", exist_ok=True)
            digest = hashlib.sha256(value.encode()).hexdigest()
            own = f"/tmp/harness_probe_coord/{{digest}}.{{side}}"
            other_side = "legacy" if side == "python" else "python"
            other = f"/tmp/harness_probe_coord/{{digest}}.{{other_side}}"
            open(own, "a").close()
            deadline = time.time() + 4
            while not os.path.exists(other) and time.time() < deadline:
                time.sleep(0.01)
            if not os.path.exists(other):
                sys.exit(88)
            sys.stdout.write("/probe")
        else:
            sys.stdout.write("/python" if side == "python" else "/legacy")
    ''')
    with open(path, "w") as f:
        f.write(program)
    os.chmod(path, 0o755)


def _run_probe(executable, mode):
    for path in ("/tmp/harness_probe.log", "/tmp/harness_probe_mode"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    shutil.rmtree("/tmp/harness_probe_coord", ignore_errors=True)
    with open("/tmp/harness_probe_mode", "w") as f:
        f.write(mode)

    result = subprocess.run(
        [executable],
        cwd="/home/user/tester",
        capture_output=True,
        text=True,
        timeout=120,
    )

    records = []
    if os.path.exists("/tmp/harness_probe.log"):
        with open("/tmp/harness_probe.log") as f:
            for line in f:
                records.append(json.loads(line))

    by_side = {"python": collections.defaultdict(list), "legacy": collections.defaultdict(list)}
    for rec in records:
        if rec.get("side") in by_side:
            by_side[rec["side"]][rec.get("value", "")].append(float(rec["time"]))

    common = set(by_side["python"]) & set(by_side["legacy"])
    assert len(common) >= 2, (
        f"Harness must send at least two generated filenames to both routers; "
        f"observed common inputs: {sorted(common)!r}"
    )

    if mode == "normal":
        concurrent = 0
        for value in common:
            closest = min(
                abs(a - b)
                for a in by_side["python"][value]
                for b in by_side["legacy"][value]
            )
            if closest < 1.5:
                concurrent += 1
        assert concurrent >= 2, "Harness did not run both routers concurrently for its test inputs"

    return result


def test_go_harness_behavior_and_source():
    source = "/home/user/tester/tester.go"
    submitted = "/home/user/bin/tester_amd64"
    _check_go_concurrency_syntax(source)

    with tempfile.TemporaryDirectory() as td:
        rebuilt_amd64 = os.path.join(td, "tester_amd64")
        rebuilt_arm64 = os.path.join(td, "tester_arm64")
        for arch, output in (("amd64", rebuilt_amd64), ("arm64", rebuilt_arm64)):
            env = os.environ.copy()
            env.update({"GOOS": "linux", "GOARCH": arch, "CGO_ENABLED": "0", "GO111MODULE": "off"})
            result = subprocess.run(
                ["go", "build", "-o", output, source],
                capture_output=True,
                text=True,
                env=env,
                timeout=120,
            )
            assert result.returncode == 0, f"tester.go does not cross-compile for linux/{arch}: {result.stderr}"

        router = "/home/user/router.py"
        oracle = "/app/legacy_router"
        router_backup = os.path.join(td, "router.original")
        oracle_backup = os.path.join(td, "legacy.original")
        os.replace(router, router_backup)
        os.replace(oracle, oracle_backup)
        try:
            _write_probe(router, "python")
            _write_probe(oracle, "legacy")

            # Exercise both the submitted amd64 artifact and a clean build of tester.go.
            for executable in (submitted, rebuilt_amd64):
                normal = _run_probe(executable, "normal")
                assert normal.returncode == 0, (
                    f"Harness failed when both router outputs matched. stderr: {normal.stderr}"
                )

                mismatch = _run_probe(executable, "mismatch")
                if mismatch.returncode == 0:
                    normal_text = normal.stdout + normal.stderr
                    mismatch_text = mismatch.stdout + mismatch.stderr
                    assert mismatch_text != normal_text and any(
                        word in mismatch_text.lower() for word in ("mismatch", "differ", "fail", "not match")
                    ), "Harness did not detect deliberately different router outputs"
        finally:
            try:
                os.unlink(router)
            except FileNotFoundError:
                pass
            try:
                os.unlink(oracle)
            except FileNotFoundError:
                pass
            os.replace(router_backup, router)
            os.replace(oracle_backup, oracle)
            for path in ("/tmp/harness_probe.log", "/tmp/harness_probe_mode"):
                try:
                    os.unlink(path)
                except FileNotFoundError:
                    pass
            shutil.rmtree("/tmp/harness_probe_coord", ignore_errors=True)


def generate_fuzz_inputs(n=1000, seed=42):
    random.seed(seed)
    chars = string.ascii_letters + string.digits + "_."
    inputs = []
    for _ in range(n):
        length = random.randint(5, 25)
        base = "".join(random.choices(chars, k=length))

        # Bias the inputs
        prob = random.random()
        if prob < 0.15:
            base = "test_" + base[5:]
        elif prob < 0.30:
            base = base[:-3] + ".go"
        elif prob < 0.45:
            insert_pos = random.randint(0, len(base))
            base = base[:insert_pos] + "config" + base[insert_pos:]
        elif prob < 0.55:
            # combination
            base = "test_" + base[5:-3] + ".go"

        # Ensure length constraints roughly if needed, but oracle handles any length
        inputs.append(base)
    return inputs


def test_fuzz_equivalence():
    agent_script = "/home/user/router.py"
    oracle_bin = "/app/legacy_router"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.isfile(oracle_bin), f"Oracle binary missing: {oracle_bin}"

    inputs = generate_fuzz_inputs(n=1000)

    for val in inputs:
        # Run oracle
        oracle_proc = subprocess.run(
            [oracle_bin, val],
            capture_output=True,
            text=True
        )
        oracle_out = oracle_proc.stdout

        # Run agent
        agent_proc = subprocess.run(
            ["python3", agent_script, val],
            capture_output=True,
            text=True
        )
        agent_out = agent_proc.stdout

        assert oracle_out == agent_out, (
            f"Output mismatch for input: '{val}'\n"
            f"Oracle output: '{oracle_out}'\n"
            f"Agent output: '{agent_out}'\n"
            f"Agent stderr: '{agent_proc.stderr}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
