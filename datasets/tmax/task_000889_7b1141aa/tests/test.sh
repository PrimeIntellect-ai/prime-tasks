#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import struct
import subprocess
import time


def test_filtered_signal_bin():
    csv_path = "/home/user/raw_sensor_data.csv"
    bin_path = "/home/user/filtered_signal.bin"

    assert os.path.exists(bin_path), f"Missing file: {bin_path}"

    rows = []
    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["sensor_id"] == "42":
                rows.append((int(row["timestamp"]), float(row["value"])))

    rows.sort(key=lambda x: x[0])
    expected_data_le = b"".join(struct.pack("<d", r[1]) for r in rows)
    expected_data_be = b"".join(struct.pack(">d", r[1]) for r in rows)
    expected_data_native = b"".join(struct.pack("d", r[1]) for r in rows)

    with open(bin_path, "rb") as f:
        actual_data = f.read()

    assert actual_data in (expected_data_le, expected_data_be, expected_data_native), \
        "Binary data in filtered_signal.bin does not match the expected values derived from the CSV."


def instruction_sequence(path, function):
    result = subprocess.run(
        ["objdump", "-d", "--no-show-raw-insn", f"--disassemble={function}", path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    sequence = []
    for line in result.stdout.splitlines():
        match = re.match(r"^\s*[0-9a-fA-F]+:\s+([a-zA-Z][a-zA-Z0-9.]*)", line)
        if match:
            sequence.append(match.group(1))
    return sequence


def test_signal_processor_compiled_for_profiling_without_optimization():
    exe_path = "/home/user/signal_processor"
    source_path = "/home/user/signal_processor.c"
    reference_path = "/tmp/reference_signal_processor"

    assert os.path.exists(exe_path), f"Missing executable file: {exe_path}"
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable"
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_path} is not an ELF executable"

    symbols = subprocess.run(
        ["nm", "-a", exe_path], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, check=True
    ).stdout
    assert re.search(r"(?:mcount|__monstartup)", symbols), \
        "Executable does not contain the instrumentation expected from compiling with -pg"

    subprocess.run(
        ["gcc", "-pg", "-O0", source_path, "-o", reference_path],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True
    )
    for function in ("moving_average", "naive_median_filter", "main"):
        actual = instruction_sequence(exe_path, function)
        expected = instruction_sequence(reference_path, function)
        assert actual, f"Missing function {function} in executable"
        assert actual == expected, \
            f"Function {function} does not have the instruction structure produced by a -pg -O0 build"


def test_notebook_executes_complete_profiling_workflow():
    nb_path = "/home/user/profile_workflow.ipynb"
    assert os.path.exists(nb_path), f"Missing file: {nb_path}"
    assert os.path.isfile(nb_path), f"Notebook path is not a regular file: {nb_path}"

    with open(nb_path, "r", encoding="utf-8") as f:
        notebook = json.load(f)
    assert notebook.get("nbformat", 0) >= 4, "Notebook is not a valid modern Jupyter notebook"

    code_cells = []
    for cell in notebook.get("cells", []):
        if cell.get("cell_type") == "code":
            source = cell.get("source", "")
            if isinstance(source, list):
                source = "".join(source)
            code_cells.append(source.lower())
    assert code_cells, "Notebook contains no code cells"

    run_cells = [i for i, src in enumerate(code_cells)
                 if "signal_processor" in src and "filtered_signal.bin" in src]
    gprof_cells = [i for i, src in enumerate(code_cells)
                   if "gprof" in src and "gmon.out" in src and "profile_results.txt" in src]
    parse_cells = [i for i, src in enumerate(code_cells)
                   if "profile_results.txt" in src and "slowest_function.txt" in src]
    assert run_cells, "Notebook has no cell that runs signal_processor on filtered_signal.bin"
    assert gprof_cells, "Notebook has no cell that runs gprof on gmon.out and writes profile_results.txt"
    assert parse_cells, "Notebook has no cell that reads the profile and writes slowest_function.txt"
    assert any(r <= g <= p for r in run_cells for g in gprof_cells for p in parse_cells), \
        "Notebook cells do not implement the required run, gprof, and parse sequence"

    generated_paths = [
        "/home/user/gmon.out",
        "/home/user/profile_results.txt",
        "/home/user/slowest_function.txt",
        "/home/user/profile_workflow.nbconvert.ipynb",
    ]
    for path in generated_paths:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    started_ns = time.time_ns()
    execution = subprocess.run(
        ["jupyter", "nbconvert", "--execute", nb_path],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert execution.returncode == 0, \
        f"Notebook execution failed:\n{execution.stdout[-4000:]}"

    for path in ("/home/user/gmon.out", "/home/user/profile_results.txt",
                 "/home/user/slowest_function.txt"):
        assert os.path.isfile(path), f"Notebook execution did not create {path}"
        assert os.stat(path).st_mtime_ns >= started_ns, f"{path} was not regenerated by notebook execution"

    fresh_gprof = subprocess.run(
        ["gprof", "/home/user/signal_processor", "/home/user/gmon.out"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout
    with open("/home/user/profile_results.txt", "rb") as f:
        notebook_report = f.read()
    assert notebook_report == fresh_gprof, \
        "profile_results.txt is not the gprof report for the submitted executable and generated gmon.out"

    report_text = fresh_gprof.decode("utf-8", errors="replace")
    flat_profile = report_text.split("Call graph", 1)[0]
    entries = []
    for line in flat_profile.splitlines():
        match = re.match(r"^\s*(\d+(?:\.\d+)?)\s+\d", line)
        if match:
            fields = line.split()
            entries.append((float(match.group(1)), fields[-1]))
    assert entries, "Could not parse any functions from the generated gprof flat profile"
    derived_slowest = max(entries, key=lambda entry: entry[0])[1]

    txt_path = "/home/user/slowest_function.txt"
    assert os.path.exists(txt_path), f"Missing file: {txt_path}"
    with open(txt_path, "r") as f:
        raw_content = f.read()
    content = raw_content.strip()
    assert content == "naive_median_filter", \
        f"Expected slowest function to be 'naive_median_filter', but got '{content}'"
    assert raw_content == derived_slowest, \
        f"slowest_function.txt must contain only the top function parsed from gprof; expected '{derived_slowest}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
