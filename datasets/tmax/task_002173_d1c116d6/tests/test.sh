#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import random
import shutil
import stat
import subprocess
import tempfile

SIM = "/home/user/sim"
SCRIPT = os.path.join(SIM, "orchestrate.sh")
SOURCE = os.path.join(SIM, "sum_potentials.c")
EXECUTABLE = os.path.join(SIM, "sum_potentials")
DATA = os.path.join(SIM, "data.txt")


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


def test_orchestrate_script_exists_and_executable():
    """Check if orchestrate.sh exists and is executable."""
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."


def test_orchestrate_execution_and_result():
    """Run orchestrate.sh and verify the result.log output."""
    result = run([SCRIPT], cwd=SIM)
    assert result.returncode == 0, (
        f"orchestrate.sh failed with return code {result.returncode}. "
        f"stderr: {result.stderr}"
    )

    log_path = os.path.join(SIM, "result.log")
    assert os.path.isfile(log_path), f"{log_path} was not created by orchestrate.sh."
    with open(log_path) as f:
        log_content = f.read().strip()
    assert log_content == "REPRODUCIBLE", (
        f"Expected result.log to contain 'REPRODUCIBLE', got '{log_content}'"
    )


def test_sum_potentials_correctness():
    """Preserve the original fixed-data correctness assertion."""
    assert os.path.isfile(EXECUTABLE), (
        f"{EXECUTABLE} is missing. Did orchestrate.sh compile it?"
    )
    result = run([EXECUTABLE, DATA])
    assert result.returncode == 0, "sum_potentials failed to execute."
    output = result.stdout.strip()
    expected_output = "10010000.000000"
    assert output == expected_output, (
        f"Expected sum_potentials to output {expected_output}, got {output}. "
        "Kahan summation may not be correctly implemented."
    )


def test_c_source_contains_kahan_logic():
    """Keep the file-reading assertions and require a real Kahan update sequence."""
    assert os.path.isfile(SOURCE), f"{SOURCE} is missing."
    with open(SOURCE) as f:
        content = f.read()

    assert "fopen" in content, "Source file seems to have lost file reading logic."
    assert "fscanf" in content, "Source file seems to have lost file parsing logic."

    # Remove comments before looking for the connected four-step Kahan recurrence.
    code = re.sub(r"/\*.*?\*/", " ", content, flags=re.S)
    code = re.sub(r"//[^\n]*", " ", code)
    ident = r"[A-Za-z_]\w*"
    standard = re.compile(
        rf"\b(?P<y>{ident})\s*=\s*(?P<v>{ident})\s*-\s*(?P<c>{ident})\s*;"
        rf".{{0,500}}?\b(?P<t>{ident})\s*=\s*(?P<s>{ident})\s*\+\s*(?P=y)\s*;"
        rf".{{0,500}}?\b(?P=c)\s*=\s*\(\s*(?P=t)\s*-\s*(?P=s)\s*\)\s*-\s*(?P=y)\s*;"
        rf".{{0,500}}?\b(?P=s)\s*=\s*(?P=t)\s*;",
        flags=re.S,
    )
    opposite_sign = re.compile(
        rf"\b(?P<y>{ident})\s*=\s*(?P<v>{ident})\s*\+\s*(?P<c>{ident})\s*;"
        rf".{{0,500}}?\b(?P<t>{ident})\s*=\s*(?P<s>{ident})\s*\+\s*(?P=y)\s*;"
        rf".{{0,500}}?\b(?P=c)\s*=\s*\(\s*(?P=s)\s*-\s*(?P=t)\s*\)\s*\+\s*(?P=y)\s*;"
        rf".{{0,500}}?\b(?P=s)\s*=\s*(?P=t)\s*;",
        flags=re.S,
    )
    assert standard.search(code) or opposite_sign.search(code), (
        "Source does not contain a connected Kahan compensation update."
    )


def test_sum_potentials_on_derived_inputs_and_orders():
    """Exercise the submitted executable on non-fixed inputs against a compiled Kahan oracle."""
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is missing."

    reference_source = r'''
#include <stdio.h>
int main(int argc, char **argv) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    float sum = 0.0f, compensation = 0.0f, value;
    while (fscanf(f, "%f", &value) == 1) {
        float y = value - compensation;
        float next = sum + y;
        compensation = (next - sum) - y;
        sum = next;
    }
    fclose(f);
    printf("%.6f\n", sum);
    return 0;
}
'''

    with tempfile.TemporaryDirectory() as td:
        ref_c = os.path.join(td, "reference.c")
        ref_exe = os.path.join(td, "reference")
        with open(ref_c, "w") as f:
            f.write(reference_source)
        compiled = run(["gcc", "-std=c99", "-O0", ref_c, "-o", ref_exe])
        assert compiled.returncode == 0, compiled.stderr

        rng = random.Random(734921)
        families = [
            [10000000.0] + [0.05] * 20000,
            [2000000.0] + [0.03] * 10000,
            # This boundary case distinguishes float Kahan accumulation from
            # merely switching the accumulator to a naive double.
            [1.0] + [0.0000001] * 5,
            [-750000.0] + [0.02] * 15000,
        ]

        for family_index, values in enumerate(families):
            orders = [list(values)]
            if len(values) > 10:
                for _ in range(3):
                    shuffled = list(values)
                    rng.shuffle(shuffled)
                    orders.append(shuffled)
            else:
                orders.extend([list(reversed(values)), values[1:] + values[:1]])

            reference_outputs = []
            for order_index, order in enumerate(orders):
                path = os.path.join(td, f"case_{family_index}_{order_index}.txt")
                with open(path, "w") as f:
                    for value in order:
                        f.write(f"{value:.17g}\n")

                expected = run([ref_exe, path])
                actual = run([EXECUTABLE, path])
                assert expected.returncode == 0
                assert actual.returncode == 0, (
                    f"sum_potentials failed on generated case {family_index}/{order_index}: "
                    f"{actual.stderr}"
                )
                assert actual.stdout == expected.stdout, (
                    f"Generated case {family_index}/{order_index}: expected Kahan output "
                    f"{expected.stdout.strip()!r}, got {actual.stdout.strip()!r}"
                )
                reference_outputs.append(expected.stdout)

            # The large-plus-small families were selected so Kahan's formatted
            # result is invariant under these independently generated orders.
            if len(values) > 10:
                assert len(set(reference_outputs)) == 1


def test_orchestrate_really_shuffles_runs_and_compares():
    """Ensure orchestration uses shuf and derives result.log from both executions."""
    controlled_source = r'''
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    if (strstr(argv[1], "data_shuffled.txt")) puts("SECOND-RUN");
    else puts("FIRST-RUN");
    return 0;
}
'''
    original_source = open(SOURCE, "rb").read()
    original_data = open(DATA, "rb").read()
    shuf_path = "/usr/bin/shuf"
    shuf_backup = f"/usr/bin/shuf.verifier-backup-{os.getpid()}"
    marker = os.path.join(tempfile.gettempdir(), f"shuf-called-{os.getpid()}")

    try:
        os.rename(shuf_path, shuf_backup)
        wrapper = f'''#!/bin/bash
echo "$@" >> {marker!r}
out=""
args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--output) out="$2"; shift 2 ;;
    --output=*) out="${{1#*=}}"; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do args+=("$1"); shift; done ;;
    *) args+=("$1"); shift ;;
  esac
done
if [ -n "$out" ]; then
  /usr/bin/tac "${{args[@]}}" > "$out"
else
  /usr/bin/tac "${{args[@]}}"
fi
'''
        with open(shuf_path, "w") as f:
            f.write(wrapper)
        os.chmod(shuf_path, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                            stat.S_IRGRP | stat.S_IXGRP |
                            stat.S_IROTH | stat.S_IXOTH)

        with open(SOURCE, "w") as f:
            f.write(controlled_source)
        controlled_lines = ["11\n", "22\n", "33\n", "44\n", "55\n"]
        with open(DATA, "w") as f:
            f.writelines(controlled_lines)

        result = run([SCRIPT], cwd=SIM)
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(marker), "orchestrate.sh did not invoke shuf."

        shuffled_path = os.path.join(SIM, "data_shuffled.txt")
        assert os.path.isfile(shuffled_path), "data_shuffled.txt was not created."
        with open(shuffled_path) as f:
            shuffled_lines = f.readlines()
        assert shuffled_lines == list(reversed(controlled_lines)), (
            "data_shuffled.txt was not created from shuf's output."
        )

        with open(os.path.join(SIM, "result.log")) as f:
            verdict = f.read().strip()
        assert verdict == "NON-REPRODUCIBLE", (
            "orchestrate.sh did not report differing outputs as NON-REPRODUCIBLE."
        )
    finally:
        with open(SOURCE, "wb") as f:
            f.write(original_source)
        with open(DATA, "wb") as f:
            f.write(original_data)
        if os.path.exists(shuf_path) and os.path.exists(shuf_backup):
            os.unlink(shuf_path)
        if os.path.exists(shuf_backup):
            os.rename(shuf_backup, shuf_path)
        if os.path.exists(marker):
            os.unlink(marker)

    # Leave the requested artifact compiled from the restored submission and
    # preserve the original successful orchestration assertion.
    restored = run([SCRIPT], cwd=SIM)
    assert restored.returncode == 0, restored.stderr
    with open(os.path.join(SIM, "result.log")) as f:
        assert f.read().strip() == "REPRODUCIBLE"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
