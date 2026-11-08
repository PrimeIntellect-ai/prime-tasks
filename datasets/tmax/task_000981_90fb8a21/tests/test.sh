#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import subprocess
import tempfile
import uuid
from decimal import Decimal
from pathlib import Path

CALC = Path("/home/user/bin/calc_det")
SCRIPT = Path("/home/user/filter_graph.sh")


def run(cmd, timeout=5):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def determinant(m):
    return (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
            - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
            + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))


def write_matrix(path, matrix):
    path.write_text("\n".join(" ".join(str(x) for x in row) for row in matrix) + "\n")


def test_calc_det_compiled():
    assert CALC.is_file(), f"Compiled executable not found at {CALC}"
    assert os.access(CALC, os.X_OK), f"File {CALC} is not executable"
    assert CALC.read_bytes()[:4] == b"\x7fELF", "calc_det must be a compiled ELF executable"

    assert run([str(CALC)]).returncode != 0, "calc_det must reject a missing matrix argument"
    assert run([str(CALC), "/dev/null", "/dev/null"]).returncode != 0, "calc_det must reject extra arguments"

    rng = random.Random(917263)
    with tempfile.TemporaryDirectory(prefix="det-check-") as td:
        td = Path(td)
        matrices = [
            [[1, 2, 3], [0, 4, 5], [1, 0, 6]],
            [[Decimal("0.25"), Decimal("-1.5"), Decimal("2")],
             [Decimal("3"), Decimal("0.125"), Decimal("-4")],
             [Decimal("2.5"), Decimal("1"), Decimal("0.75")]],
        ]
        for _ in range(12):
            matrices.append([[rng.randint(-7, 7) for _ in range(3)] for _ in range(3)])

        for i, matrix in enumerate(matrices):
            p = td / f"{uuid.uuid4().hex}.dat"
            write_matrix(p, matrix)
            result = run([str(CALC), str(p)])
            assert result.returncode == 0, f"calc_det failed on generated matrix {i}: {result.stderr}"
            output = result.stdout.strip()
            assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", output), \
                f"calc_det produced a non-numeric result: {output!r}"
            expected = float(determinant([[Decimal(str(x)) for x in row] for row in matrix]))
            assert abs(float(output) - expected) <= 5.1e-6, \
                f"wrong determinant for generated matrix {i}: got {output}, expected {expected}"


def test_filter_graph_script_exists_and_executable():
    assert SCRIPT.is_file(), f"Script not found at {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable"
    first_line = SCRIPT.read_text(errors="replace").splitlines()[0] if SCRIPT.stat().st_size else ""
    assert re.match(r"^#!.*(?:/|\b)bash(?:\s|$)", first_line), "filter_graph.sh must be a Bash script"


def test_adversarial_corpus():
    evil_corpus_dir = Path("/app/corpus/evil")
    clean_corpus_dir = Path("/app/corpus/clean")

    evil_files = list(evil_corpus_dir.glob("*.txt"))
    clean_files = list(clean_corpus_dir.glob("*.txt"))

    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    for evil_file in evil_files:
        result = run([str(SCRIPT), str(evil_file)])
        if result.returncode != 1:
            evil_bypassed.append(evil_file.name)

    clean_modified = []
    for clean_file in clean_files:
        result = run([str(SCRIPT), str(clean_file)])
        if result.returncode != 0:
            clean_modified.append(clean_file.name)

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(evil_bypassed[:5])}{'...' if len(evil_bypassed) > 5 else ''}")
    if clean_modified:
        error_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(clean_modified[:5])}{'...' if len(clean_modified) > 5 else ''}")

    assert not evil_bypassed and not clean_modified, " | ".join(error_msg)


def test_hidden_matrices_threshold_arguments_and_calc_usage():
    assert run([str(SCRIPT)]).returncode != 0, "filter_graph.sh must reject zero arguments"
    assert run([str(SCRIPT), "/dev/null", "/dev/null"]).returncode != 0, \
        "filter_graph.sh must reject more than one argument"

    rng = random.SystemRandom()
    targets = [
        Decimal("0"), Decimal("0.0002"), Decimal("-0.0017"),
        Decimal("0.0040"), Decimal("-0.0048"), Decimal("0.0049"),
        Decimal("0.005"), Decimal("-0.005"), Decimal("0.0052"),
        Decimal("-0.006"), Decimal("0.021"), Decimal("-0.4"), Decimal("1.75")
    ]
    for _ in range(15):
        if rng.randrange(2):
            targets.append(Decimal(rng.randrange(-4500, 4501)) / Decimal(1000000))
        else:
            magnitude = Decimal(rng.randrange(5500, 200000)) / Decimal(1000000)
            targets.append(magnitude if rng.randrange(2) else -magnitude)
    rng.shuffle(targets)

    work = Path(tempfile.mkdtemp(prefix=f"matrix-{uuid.uuid4().hex}-"))
    backup_dir = Path(tempfile.mkdtemp(prefix="calc-backup-"))
    real_calc = backup_dir / "original_calc_det"
    log_path = backup_dir / "calls.log"
    cases = []

    try:
        for target in targets:
            # L*diag(target,1,1)*U with unit-triangular integer L and U.
            # Its determinant is target, but its entries and layout vary per case.
            a, b, c, d, e, f = [rng.randrange(-5, 6) for _ in range(6)]
            L = [[Decimal(1), Decimal(0), Decimal(0)],
                 [Decimal(a), Decimal(1), Decimal(0)],
                 [Decimal(b), Decimal(c), Decimal(1)]]
            U = [[Decimal(1), Decimal(d), Decimal(e)],
                 [Decimal(0), Decimal(1), Decimal(f)],
                 [Decimal(0), Decimal(0), Decimal(1)]]
            D = [[target, Decimal(0), Decimal(0)],
                 [Decimal(0), Decimal(1), Decimal(0)],
                 [Decimal(0), Decimal(0), Decimal(1)]]

            def mul(x, y):
                return [[sum(x[i][k] * y[k][j] for k in range(3)) for j in range(3)] for i in range(3)]

            matrix = mul(mul(L, D), U)
            derived = determinant(matrix)
            p = work / f"{uuid.uuid4().hex}.matrix"
            write_matrix(p, matrix)
            cases.append((p, 1 if abs(derived) < Decimal("0.005") else 0))

        # Interpose a transparent logger to prove the sanitizer actually invokes
        # the required compiled tool for each hidden input.
        shutil.move(str(CALC), str(real_calc))
        CALC.write_text(
            "#!/bin/bash\n"
            f"printf '%s\\n' \"$1\" >> {str(log_path)!r}\n"
            f"exec {str(real_calc)!r} \"$@\"\n"
        )
        CALC.chmod(0o755)

        failures = []
        for p, expected_rc in cases:
            result = run([str(SCRIPT), str(p)])
            if result.returncode != expected_rc:
                failures.append(f"{p.name}: expected exit {expected_rc}, got {result.returncode}")
        assert not failures, "Hidden determinant classifications failed: " + "; ".join(failures[:8])

        logged = set(log_path.read_text().splitlines()) if log_path.exists() else set()
        missing = [p.name for p, _ in cases if str(p) not in logged]
        assert not missing, "filter_graph.sh did not invoke /home/user/bin/calc_det for: " + ", ".join(missing[:8])
    finally:
        if real_calc.exists():
            if CALC.exists():
                CALC.unlink()
            shutil.move(str(real_calc), str(CALC))
        shutil.rmtree(work, ignore_errors=True)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
