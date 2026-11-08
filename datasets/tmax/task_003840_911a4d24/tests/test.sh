#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile

SOURCE = "/home/user/model_fit.c"
EXECUTABLE = "/home/user/model_fit"
DATA = "/home/user/molecule.dat"
OUTPUT = "/home/user/fixed_output.txt"


def read_data():
    with open(DATA, "r") as f:
        fields = f.read().split()
    n = int(fields[0])
    return [float(x) for x in fields[1:n + 1]]


def iterate_in_place(values):
    potentials = list(values)
    n = len(potentials)
    # Match the unchanged C loop: updates are in place, so a node observes
    # the already-updated value of its left neighbor.
    for _ in range(10):
        for i in range(1, n - 1):
            potentials[i] = (
                potentials[i - 1] + potentials[i + 1] + potentials[i]
            ) / 3.0
    return potentials


def iterate_synchronously(values):
    potentials = list(values)
    n = len(potentials)
    for _ in range(10):
        new_potentials = potentials[:]
        for i in range(1, n - 1):
            new_potentials[i] = (
                potentials[i - 1] + potentials[i + 1] + potentials[i]
            ) / 3.0
        potentials = new_potentials
    return potentials


def kahan_sum(values):
    total_energy = 0.0
    c = 0.0
    for value in values:
        y = value - c
        t = total_energy + y
        c = (t - total_energy) - y
        total_energy = t
    return total_energy


def naive_sum(values):
    total = 0.0
    for value in values:
        total += value
    return total


def get_expected_energy():
    return kahan_sum(iterate_in_place(read_data()))


def expected_output(values):
    energy = kahan_sum(iterate_in_place(values))
    return f"Total Energy: {energy:.10f}\n"


def write_data(values):
    with open(DATA, "w") as f:
        f.write(str(len(values)) + "\n")
        for value in values:
            f.write(format(value, ".17g") + "\n")


def run_program(path):
    result = subprocess.run(
        [path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10, check=False
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )
    return result.stdout


def make_discriminating_cases():
    # Deterministically search for cancellation-heavy inputs. Expected answers
    # are derived here rather than stored in the image.
    state = 0x5EED1234
    cases = []
    found_kahan = False
    found_in_place = False
    scales = [1.0, 1e4, 1e8, 1e12, 1e16]

    for attempt in range(3000):
        values = []
        for i in range(31):
            state = (1664525 * state + 1013904223) & 0xFFFFFFFF
            scale = scales[(state >> 8) % len(scales)]
            sign = -1.0 if state & 1 else 1.0
            fraction = ((state >> 12) & 0xFFFF) / 65536.0
            values.append(sign * scale * (1.0 + fraction))

        in_place = iterate_in_place(values)
        kahan_text = f"{kahan_sum(in_place):.10f}"
        naive_text = f"{naive_sum(in_place):.10f}"
        sync_text = f"{kahan_sum(iterate_synchronously(values)):.10f}"

        distinguishes_kahan = kahan_text != naive_text
        distinguishes_iteration = kahan_text != sync_text
        if (distinguishes_kahan and not found_kahan) or (
            distinguishes_iteration and not found_in_place
        ):
            cases.append(values)
            found_kahan = found_kahan or distinguishes_kahan
            found_in_place = found_in_place or distinguishes_iteration
        if found_kahan and found_in_place:
            break

    assert found_kahan, "Could not construct a Kahan-discriminating test input"
    assert found_in_place, "Could not construct an in-place-iteration test input"
    return cases


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), "The compiled executable /home/user/model_fit is missing."
    assert os.access(EXECUTABLE, os.X_OK), "/home/user/model_fit is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/model_fit is not a compiled ELF executable."


def test_output_file_exists():
    assert os.path.isfile(OUTPUT), "The output file /home/user/fixed_output.txt is missing."


def test_kahan_summation_output():
    expected_energy = get_expected_energy()
    expected_output_str = f"Total Energy: {expected_energy:.10f}"

    with open(OUTPUT, "r") as f:
        output_content = f.read().strip()

    match = re.search(r"Total Energy:\s*([+-]?[0-9]+\.[0-9]+)", output_content)
    assert match is not None, "Could not find 'Total Energy: <number>' in fixed_output.txt"
    actual_energy = float(match.group(1))
    assert abs(actual_energy - expected_energy) < 1e-5, (
        f"Expected energy close to {expected_energy:.10f}, but got {actual_energy}"
    )

    # The requested file must be the exact stdout of the submitted executable.
    actual_stdout = run_program(EXECUTABLE)
    with open(OUTPUT, "rb") as f:
        saved_stdout = f.read()
    assert saved_stdout == actual_stdout, (
        "fixed_output.txt is not the exact output currently produced by model_fit"
    )
    assert actual_stdout == (expected_output_str + "\n").encode(), (
        "The executable does not produce the expected in-place-iteration/Kahan result"
    )


def test_source_code_modified():
    with open(SOURCE, "r") as f:
        content = f.read()

    # Preserve the original source assertion.
    assert "total_energy = t" in content or "c =" in content or "y =" in content, (
        "Could not find Kahan summation logic in model_fit.c"
    )
    assert not re.search(r"total_energy\s*\+=\s*potentials\s*\[\s*i\s*\]", content), (
        "The original naive summation is still present"
    )

    # Confirm that the original in-place iteration itself remains in the source.
    loop = re.compile(
        r"for\s*\(\s*int\s+iter\s*=\s*0\s*;\s*iter\s*<\s*10\s*;\s*iter\+\+\s*\)\s*\{"
        r"\s*for\s*\(\s*int\s+i\s*=\s*1\s*;\s*i\s*<\s*N\s*-\s*1\s*;\s*i\+\+\s*\)\s*\{"
        r"\s*potentials\s*\[\s*i\s*\]\s*=\s*\(\s*potentials\s*\[\s*i\s*-\s*1\s*\]"
        r"\s*\+\s*potentials\s*\[\s*i\s*\+\s*1\s*\]\s*\+\s*potentials\s*\[\s*i\s*\]\s*\)\s*/\s*3\.0\s*;"
        r"\s*\}\s*\}", re.S
    )
    assert loop.search(content), "The original in-place iteration loop was changed"


def test_compiled_behavior_on_derived_inputs():
    original_data = open(DATA, "rb").read()
    fd, rebuilt = tempfile.mkstemp(prefix="model_fit_rebuilt_", dir="/tmp")
    os.close(fd)
    os.unlink(rebuilt)
    try:
        compile_result = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt, "-lm"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert compile_result.returncode == 0, (
            "model_fit.c does not compile with the required command: "
            + compile_result.stderr.decode(errors="replace")
        )

        for values in make_discriminating_cases():
            write_data(values)
            expected = expected_output(values).encode()
            assert run_program(EXECUTABLE) == expected, (
                "The submitted executable failed a derived cancellation/iteration case"
            )
            assert run_program(rebuilt) == expected, (
                "The submitted source failed a derived cancellation/iteration case"
            )
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
