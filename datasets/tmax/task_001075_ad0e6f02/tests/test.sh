#!/bin/bash
set -e
mkdir -p /logs/verifier
reward=0
trap 'printf "%s\n" "$reward" > /logs/verifier/reward.txt' EXIT

AGENT_PATH=/home/user/replicated_integrator.sh
SANDBOX=$(mktemp -d /tmp/integrator-sandbox.XXXXXX)
chmod 755 "$SANDBOX"

cat > /tmp/reference_integrator.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 5) return 1;
    double r = atof(argv[1]);
    double v = atof(argv[2]);
    double dt = atof(argv[3]);
    int steps = atoi(argv[4]);

    for (int i = 0; i < steps; i++) {
        double a = -1.0 / (r * r);
        r += v * dt;
        v += a * dt;
        dt = dt * 1.01;
        if (dt > 0.5) dt = 0.5;
    }
    printf("%.6f %.6f\n", r, v);
    return 0;
}
EOF
gcc -O2 /tmp/reference_integrator.c -o /tmp/reference_integrator

copy_program() {
    local src="$1"
    local dst="$2"
    local real lib
    real=$(readlink -f "$src")
    mkdir -p "$SANDBOX$(dirname "$dst")"
    cp "$real" "$SANDBOX$dst"
    while IFS= read -r lib; do
        [ -n "$lib" ] || continue
        mkdir -p "$SANDBOX$(dirname "$lib")"
        cp -n "$lib" "$SANDBOX$lib"
    done < <(ldd "$real" 2>/dev/null | awk '{ for (i=1; i<=NF; i++) if ($i ~ /^\//) print $i }')
}

# Supply the interpreters and ordinary text/numeric tools permitted by the task,
# but deliberately do not expose /app or any other agent-created files.
copy_program /bin/bash /bin/bash
copy_program /bin/bash /bin/sh
for p in awk gawk bc env sed grep cut tr head tail seq cat expr printf; do
    if command -v "$p" >/dev/null 2>&1; then
        copy_program "$(command -v "$p")" "/usr/bin/$p"
    fi
done

mkdir -p "$SANDBOX/home/user" "$SANDBOX/tmp"
cp "$AGENT_PATH" "$SANDBOX/home/user/replicated_integrator.sh" 2>/dev/null || true
chmod -R a-w "$SANDBOX"
find "$SANDBOX" -type d -exec chmod 555 {} +
[ ! -e "$SANDBOX/home/user/replicated_integrator.sh" ] || chmod 555 "$SANDBOX/home/user/replicated_integrator.sh"

cat > /tmp/test_final_state.py <<'PYEOF'
import os
import random
import subprocess

ORACLE_PATH = "/app/binary_integrator"
REFERENCE_PATH = "/tmp/reference_integrator"
AGENT_PATH = "/home/user/replicated_integrator.sh"
SANDBOX = os.environ["INTEGRATOR_SANDBOX"]
NUM_TESTS = 100


def test_agent_script_exists_and_executable():
    assert os.path.exists(AGENT_PATH), f"Agent script missing at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"{AGENT_PATH} is not executable"

    with open(AGENT_PATH, "rb") as f:
        data = f.read()
    assert not data.startswith(b"\x7fELF"), "Submission must be a Bash script, not an ELF executable"
    assert b"\x00" not in data, "Submission must be a text Bash script"
    first_line = data.splitlines()[0] if data.splitlines() else b""
    assert first_line.startswith(b"#!") and b"bash" in first_line, "Submission must use a Bash shebang"

    # The reference executable is intentionally available for analysis, but an
    # executable copy is not a valid pure-Bash submission.
    with open(ORACLE_PATH, "rb") as f:
        assert data != f.read(), "Submission is byte-identical to the provided binary"


def run_reference(args):
    try:
        result = subprocess.run(
            [REFERENCE_PATH] + args,
            capture_output=True,
            text=True,
            check=True,
            timeout=5,
        )
    except subprocess.CalledProcessError as e:
        raise AssertionError(f"Reference failed on input {args}: {e.stderr}") from e
    except subprocess.TimeoutExpired as e:
        raise AssertionError(f"Reference timed out on input {args}") from e
    return result.stdout.strip()


def run_agent(args):
    cmd = [
        "/usr/sbin/chroot",
        "--userspec=65534:65534",
        SANDBOX,
        AGENT_PATH,
    ] + args
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
            timeout=5,
            env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"},
        )
    except subprocess.CalledProcessError as e:
        raise AssertionError(f"Agent script failed on input {args}: {e.stderr}") from e
    except subprocess.TimeoutExpired as e:
        raise AssertionError(f"Agent script timed out on input {args}") from e
    return result.stdout.strip()


def check_case(args, label):
    expected = run_reference(args)
    actual = run_agent(args)
    assert actual == expected, (
        f"Output mismatch on {label}.\n"
        f"Inputs: r={args[0]}, v={args[1]}, dt={args[2]}, steps={args[3]}\n"
        f"Reference output: '{expected}'\n"
        f"Agent output:     '{actual}'"
    )


def test_fuzz_equivalence():
    # Preserve the original seeded fuzz coverage.
    random.seed(42)
    for i in range(NUM_TESTS):
        r = random.uniform(5.0, 20.0)
        v = random.uniform(0.0, 2.0)
        dt = random.uniform(0.001, 0.1)
        steps = random.randint(10, 500)
        args = [f"{r:.6f}", f"{v:.6f}", f"{dt:.6f}", str(steps)]
        check_case(args, f"seeded test {i + 1}/{NUM_TESTS}")

    # Add verifier-time inputs so a table of the public seeded answers is not enough.
    rng = random.SystemRandom()
    for i in range(20):
        r = rng.uniform(5.0, 20.0)
        v = rng.uniform(0.0, 2.0)
        dt = rng.uniform(0.001, 0.1)
        steps = rng.randint(10, 500)
        args = [f"{r:.9f}", f"{v:.9f}", f"{dt:.9f}", str(steps)]
        check_case(args, f"runtime fuzz test {i + 1}/20")
PYEOF

if INTEGRATOR_SANDBOX="$SANDBOX" python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
