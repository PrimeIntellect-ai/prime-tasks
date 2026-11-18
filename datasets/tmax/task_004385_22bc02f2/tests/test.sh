#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import stat
import subprocess
import tempfile


def assert_regular_file(path, description):
    try:
        mode = os.lstat(path).st_mode
    except FileNotFoundError:
        raise AssertionError(f"Expected {description} at {path} does not exist.")
    assert stat.S_ISREG(mode), f"Expected {description} at {path} to be a regular file, not a symlink or other file type."


def run_in_empty_chroot(binary, expr):
    with tempfile.TemporaryDirectory(prefix="calc-root-") as root:
        target = os.path.join(root, "calc")
        shutil.copyfile(binary, target)
        os.chmod(target, 0o755)
        return subprocess.run(
            ["chroot", root, "/calc", expr],
            capture_output=True,
            text=True,
            timeout=2,
        )


def test_go_calc_exists_and_executable():
    agent_bin = "/app/bin/go_calc"
    assert_regular_file(agent_bin, "Go binary")
    assert os.access(agent_bin, os.X_OK), f"Go binary at {agent_bin} is not executable."

    metadata = subprocess.run(
        ["go", "version", "-m", agent_bin],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert metadata.returncode == 0 and "go1" in metadata.stdout, (
        f"{agent_bin} is not recognizable as a Go executable.\n"
        f"stdout: {metadata.stdout}\nstderr: {metadata.stderr}"
    )


def test_source_and_ci_then_fuzz_equivalence():
    oracle_bin = "/app/bin/legacy_calc"
    agent_bin = "/app/bin/go_calc"
    source = "/app/src/calc.go"
    ci_script = "/app/ci/test.sh"

    assert_regular_file(oracle_bin, "oracle binary")
    assert_regular_file(source, "Go source")
    assert_regular_file(ci_script, "CI test script")

    ci_res = subprocess.run(
        ["bash", ci_script],
        cwd="/app",
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert ci_res.returncode == 0, (
        f"CI script failed with exit code {ci_res.returncode}.\n"
        f"stdout: {ci_res.stdout}\nstderr: {ci_res.stderr}"
    )

    # Compile calc.go ourselves with cgo disabled, so a passing submission must
    # contain buildable pure-Go source rather than only a copied legacy binary.
    build_dir = tempfile.mkdtemp(prefix="verify-go-build-")
    built_from_source = os.path.join(build_dir, "go_calc")
    env = os.environ.copy()
    env["CGO_ENABLED"] = "0"
    env["GO111MODULE"] = "off"
    build_res = subprocess.run(
        ["go", "build", "-o", built_from_source, source],
        cwd="/app",
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert build_res.returncode == 0, (
        f"Failed to compile {source} as a pure-Go program.\n"
        f"stdout: {build_res.stdout}\nstderr: {build_res.stderr}"
    )
    assert os.path.isfile(built_from_source) and os.access(built_from_source, os.X_OK)

    random.seed(42)

    def generate_expr(depth=0):
        if depth > 2 or random.random() < 0.4:
            return str(random.randint(1, 1000))
        op = random.choice([' + ', ' - ', ' * ', ' / '])
        left = generate_expr(depth + 1)
        right = generate_expr(depth + 1)
        expr = f"{left}{op}{right}"
        if random.random() < 0.3:
            expr = f"({expr})"
        return expr

    valid_cases = []
    while len(valid_cases) < 2000:
        expr = generate_expr()
        if len(expr) > 50:
            continue
        try:
            res = subprocess.run(
                [oracle_bin, expr], capture_output=True, text=True, timeout=0.5
            )
            if res.returncode == 0 and "Result:" in res.stdout and "Checksum:" in res.stdout:
                valid_cases.append((expr, res.stdout))
        except subprocess.TimeoutExpired:
            pass
        except Exception:
            pass

    try:
        # Run both the submitted executable and a verifier-built executable in
        # an empty chroot. A copy of, or wrapper around, legacy_calc cannot pass
        # by invoking the oracle from /app.
        for expr, oracle_stdout in valid_cases:
            for candidate, label in (
                (agent_bin, "submitted Go binary"),
                (built_from_source, "binary built from /app/src/calc.go"),
            ):
                result = run_in_empty_chroot(candidate, expr)
                assert result.returncode == 0, (
                    f"{label} crashed or failed on input '{expr}'.\n"
                    f"Stderr: {result.stderr}"
                )
                assert oracle_stdout == result.stdout, (
                    f"Mismatch from {label} on input '{expr}'\n"
                    f"Oracle output: {oracle_stdout.strip()}\n"
                    f"Agent output:  {result.stdout.strip()}"
                )
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
