#!/bin/bash
set -u
mkdir -p /logs/verifier

backup="/tmp/.solve_ode.verifier-backup.$$"
marker="/tmp/.solve_ode.invoked.$$"
rm -f "$marker" "$backup"

cleanup() {
    if [ -e "$backup" ]; then
        rm -f /app/solve_ode
        mv "$backup" /app/solve_ode
    fi
    rm -f "$marker"
}
trap cleanup EXIT

if ! mv /app/solve_ode "$backup"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat > /app/solve_ode <<EOF
#!/bin/bash
printf 'invoked\n' > '$marker'
exit 97
EOF
chmod 755 /app/solve_ode
export SOLVE_ODE_GUARD_MARKER="$marker"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
import uuid
from decimal import Decimal

import pytest

SCRIPT = "/home/user/filter.sh"
MARKER = os.environ["SOLVE_ODE_GUARD_MARKER"]


def run_filter(path):
    return subprocess.run(
        [SCRIPT, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    ).returncode


def test_filter_script_exists_and_executable():
    script_path = "/home/user/filter.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_clean_corpus_accepted():
    script_path = "/home/user/filter.sh"
    clean_corpus_path = "/truth/clean_corpus/"
    assert os.path.exists(clean_corpus_path), f"Directory {clean_corpus_path} does not exist."

    files = sorted([f for f in os.listdir(clean_corpus_path) if os.path.isfile(os.path.join(clean_corpus_path, f))])
    assert len(files) > 0, "Clean corpus is empty."

    failed_files = []
    for f in files:
        file_path = os.path.join(clean_corpus_path, f)
        result = subprocess.run([script_path, file_path], capture_output=True, timeout=5)
        if result.returncode != 0:
            failed_files.append(f)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(files)} clean modified (rejected). Offending files: {', '.join(failed_files)}")


def test_evil_corpus_rejected():
    script_path = "/home/user/filter.sh"
    evil_corpus_path = "/truth/evil_corpus/"
    assert os.path.exists(evil_corpus_path), f"Directory {evil_corpus_path} does not exist."

    files = sorted([f for f in os.listdir(evil_corpus_path) if os.path.isfile(os.path.join(evil_corpus_path, f))])
    assert len(files) > 0, "Evil corpus is empty."

    bypassed_files = []
    for f in files:
        file_path = os.path.join(evil_corpus_path, f)
        result = subprocess.run([script_path, file_path], capture_output=True, timeout=5)
        if result.returncode != 1:
            bypassed_files.append(f)

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(files)} evil bypassed (accepted or wrong exit code). Offending files: {', '.join(bypassed_files)}")


def test_novel_and_boundary_inputs_are_classified_from_contents():
    # These cases include both sides of each boundary, equality, alpha zero,
    # and negative alpha whose product would otherwise appear safe.
    cases = [
        ("0.0", "4.0", "-0.5"),
        ("0.0", "4.0", "0.0"),
        ("2.0", "3.0", "5.5"),
        ("2.0", "3.0", "6.0"),
        ("2.0", "3.0", "6.5"),
        ("-0.5", "-20.0", "9.5"),
        ("0.5", "0.5", "0.0"),
        ("0.5", "0.5", "0.25"),
        ("0.5", "0.5", "0.5"),
    ]

    rng = random.SystemRandom()
    for _ in range(160):
        alpha = rng.randint(-30, 30)
        beta = rng.randint(-30, 30)
        product = alpha * beta
        if rng.randrange(2):
            gamma = product + rng.choice([-2, -1, 0, 1, 2])
        else:
            gamma = rng.randint(-900, 900)
        cases.append((f"{alpha}.0", f"{beta}.0", f"{gamma}.0"))

    rng.shuffle(cases)
    directory = tempfile.mkdtemp(prefix=f".cfg_{uuid.uuid4().hex}_")
    failures = []

    for alpha, beta, gamma in cases:
        path = os.path.join(directory, uuid.uuid4().hex)
        with open(path, "w", encoding="ascii") as config:
            config.write(f"alpha={alpha}\nbeta={beta}\ngamma={gamma}\n")

        expected = 0 if Decimal(alpha) >= 0 and Decimal(alpha) * Decimal(beta) > Decimal(gamma) else 1
        actual = run_filter(path)
        if actual != expected:
            failures.append((alpha, beta, gamma, expected, actual))

    assert not failures, f"Novel configurations misclassified: {failures[:10]}"


def test_classifier_did_not_invoke_solve_ode():
    assert not os.path.exists(MARKER), "/home/user/filter.sh invoked /app/solve_ode during classification"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
