#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
from pathlib import Path

import pytest

HOME = Path("/home/user")
CANONICAL_CSV = """id,value
1,10.5
2,12.0
3,15.2
4,18.1
5,14.3
6,19.5
"""


def run(cmd, cwd=HOME, timeout=30):
    result = subprocess.run(
        cmd,
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, f"Command {cmd!r} failed:\n{result.stdout}"
    return result.stdout


def read_output():
    path = HOME / "output.txt"
    assert path.is_file(), f"Output file {path} is missing. Ensure you run the compiled processor."
    with path.open() as f:
        return [line.strip() for line in f if line.strip()]


def execute_processor(csv_text):
    (HOME / "data.csv").write_text(csv_text)
    output = HOME / "output.txt"
    if output.exists():
        output.unlink()
    run(["./processor"])
    return read_output()


@pytest.fixture(scope="session", autouse=True)
def clean_build_and_run():
    build = HOME / "build.sh"
    assert build.is_file(), f"File {build} is missing. You need to write a build script."

    for name in ("libmathops.so", "processor", "output.txt"):
        path = HOME / name
        if path.exists() or path.is_symlink():
            path.unlink()

    run(["bash", "build.sh"])
    assert (HOME / "libmathops.so").is_file(), "build.sh did not create libmathops.so"
    assert (HOME / "processor").is_file(), "build.sh did not create processor"
    execute_processor(CANONICAL_CSV)


def test_build_sh_exists():
    path = "/home/user/build.sh"
    assert os.path.isfile(path), f"File {path} is missing. You need to write a build script."


def test_shared_library_exists():
    path = "/home/user/libmathops.so"
    assert os.path.isfile(path), f"Shared library {path} is missing. Ensure your build script compiles it."


def test_processor_executable_exists():
    path = "/home/user/processor"
    assert os.path.isfile(path), f"Executable {path} is missing. Ensure your build script compiles it."
    st = os.stat(path)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"{path} is not executable."


def test_output_txt_content():
    expected = ["17.30", "15.87", "15.10", "12.57"]
    lines = read_output()
    assert lines == expected, (
        f"Content of /home/user/output.txt does not match the expected descending "
        f"moving averages. Got {lines}, expected {expected}."
    )


def test_artifacts_are_elf_and_dynamically_linked():
    library_header = run(["readelf", "-h", "libmathops.so"])
    processor_header = run(["readelf", "-h", "processor"])
    assert "Type:" in library_header and "DYN" in library_header, "libmathops.so is not an ELF shared object"
    assert "Type:" in processor_header and ("DYN" in processor_header or "EXEC" in processor_header), \
        "processor is not an ELF executable"

    dynamic = run(["readelf", "-d", "processor"])
    assert "Shared library: [libmathops.so]" in dynamic, "processor does not dynamically depend on libmathops.so"

    processor_symbols = run(["nm", "-D", "processor"])
    assert any(" U compute_mean" in line for line in processor_symbols.splitlines()), \
        "processor does not have an unmangled dynamic reference to compute_mean"
    assert "_Z12compute_mean" not in processor_symbols, "compute_mean still has C++ name mangling"

    library_symbols = run(["nm", "-D", "--defined-only", "libmathops.so"])
    assert any(line.split()[-1] == "compute_mean" for line in library_symbols.splitlines() if line.split()), \
        "libmathops.so does not export compute_mean"

    linkage = run(["ldd", "./processor"])
    matching = [line for line in linkage.splitlines() if "libmathops.so" in line]
    assert matching and "not found" not in matching[0], "The runtime linker cannot find libmathops.so"
    if "=>" in matching[0]:
        resolved = matching[0].split("=>", 1)[1].split("(", 1)[0].strip()
        resolved_path = Path(resolved) if os.path.isabs(resolved) else HOME / resolved
        assert resolved_path.resolve() == (HOME / "libmathops.so").resolve(), \
            f"processor resolves libmathops.so from the wrong location: {resolved}"


def test_parses_changed_csv_and_computes_overlapping_windows():
    values = [4.0, -2.0, 10.0, 8.0, 0.0, 6.0]
    csv_text = "id,value\n" + "".join(
        f"{900000 + i},{value}\n" for i, value in enumerate(values, 1)
    )
    means = [sum(values[i:i + 3]) / 3 for i in range(len(values) - 2)]
    expected = [f"{value:.2f}" for value in sorted(means, reverse=True)]
    assert execute_processor(csv_text) == expected


def test_processor_uses_compute_mean_result_from_shared_library(tmp_path):
    original_library = tmp_path / "libmathops.original.so"
    shutil.copy2(HOME / "libmathops.so", original_library)
    probe_source = tmp_path / "probe.c"
    probe_source.write_text(
        "double compute_mean(double *data, int n) {\n"
        "    if (n != 3) return -999999.0;\n"
        "    return data[0] + 10.0*data[1] + 100.0*data[2] + 0.25;\n"
        "}\n"
    )
    try:
        run(["gcc", "-shared", "-fPIC", str(probe_source), "-o", str(HOME / "libmathops.so")], cwd=tmp_path)
        values = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
        csv_text = "id,value\n" + "".join(f"{i},{value}\n" for i, value in enumerate(values, 1))
        probe_results = [
            values[i] + 10.0 * values[i + 1] + 100.0 * values[i + 2] + 0.25
            for i in range(len(values) - 2)
        ]
        expected = [f"{value:.2f}" for value in sorted(probe_results, reverse=True)]
        assert execute_processor(csv_text) == expected, \
            "processor did not use compute_mean's returned value for every overlapping window"
    finally:
        shutil.copy2(original_library, HOME / "libmathops.so")
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
