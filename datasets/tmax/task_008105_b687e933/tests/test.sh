#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shlex
import stat
import subprocess
import tempfile
from pathlib import Path

SCRIPT = Path("/home/user/run_mc.sh")
HISTOGRAM = Path("/home/user/histogram.txt")
EXPERIMENT = Path("/home/user/experiment.nc")


def expected_histogram(base_offset):
    bash_script = f"""
    RANDOM=12345
    declare -A counts
    for i in {{1..10000}}; do
      val=$(( {base_offset} + (RANDOM % 7) ))
      ((counts[$val]++))
    done

    for ((val={base_offset}; val<={base_offset + 6}; val++)); do
      c=${{counts[$val]:-0}}
      stars=$(( c / 50 ))
      star_str=""
      for ((j=0; j<stars; j++)); do
          star_str="${{star_str}}*"
      done
      printf "%d: %s\\n" "$val" "$star_str"
    done
    """
    result = subprocess.run(
        ["bash", "-c", bash_script], capture_output=True, text=True, check=True
    )
    return result.stdout.strip()


def install_experiment(base_offset):
    with tempfile.TemporaryDirectory() as directory:
        cdl = Path(directory) / "experiment.cdl"
        output = Path(directory) / "experiment.nc"
        cdl.write_text(
            "netcdf experiment {\n"
            "variables:\n"
            "    int base_offset ;\n"
            "data:\n"
            f"    base_offset = {base_offset} ;\n"
            "}\n"
        )
        subprocess.run(["ncgen", "-o", str(output), str(cdl)], check=True)
        os.replace(output, EXPERIMENT)
        os.chmod(EXPERIMENT, 0o777)


def test_run_mc_sh_exists():
    """Verify that the bash script run_mc.sh was created."""
    assert os.path.isfile(SCRIPT), "/home/user/run_mc.sh does not exist."


def test_histogram_txt_exists():
    """Verify that the histogram.txt file was generated."""
    assert os.path.isfile(HISTOGRAM), "/home/user/histogram.txt does not exist."


def test_script_contains_required_operations():
    """Verify that the submitted artifact is a Bash script implementing the requested operations."""
    source = SCRIPT.read_text()
    active_source = "\n".join(line.split("#", 1)[0] for line in source.splitlines())

    assert re.search(r"\bncdump\b", active_source), "run_mc.sh must use ncdump."
    assert re.search(r"\bbase_offset\b", active_source), "run_mc.sh must extract base_offset."
    assert "/home/user/experiment.nc" in active_source, "run_mc.sh must read experiment.nc."
    assert re.search(r"\bRANDOM[ \t]*=[ \t]*12345\b", active_source), (
        "run_mc.sh must assign RANDOM=12345."
    )
    assert re.search(r"\bRANDOM[ \t]*%[ \t]*7\b", active_source), (
        "run_mc.sh must calculate RANDOM % 7."
    )
    assert re.search(r"\b10000\b", active_source), "run_mc.sh must simulate 10,000 samples."


def test_script_execution_and_dynamic_input():
    """Execute the submitted script and test it against an unpredictable NetCDF value."""
    original_nc = EXPERIMENT.read_bytes()
    original_mode = stat.S_IMODE(EXPERIMENT.stat().st_mode)

    ncdump_path = Path("/usr/bin/ncdump")
    ncdump_backup = Path(f"/usr/bin/.ncdump.verifier.{os.getpid()}")
    marker = Path(f"/tmp/ncdump-called-{os.getpid()}")

    os.rename(ncdump_path, ncdump_backup)
    ncdump_path.write_text(
        "#!/bin/sh\n"
        f"printf 'called\\n' >> {shlex.quote(str(marker))}\n"
        f"exec {shlex.quote(str(ncdump_backup))} \"$@\"\n"
    )
    os.chmod(ncdump_path, 0o755)

    try:
        alternate_offset = random.SystemRandom().choice(
            [value for value in range(30, 500) if value != 12]
        )

        for offset in (alternate_offset, 12):
            install_experiment(offset)
            marker.unlink(missing_ok=True)
            HISTOGRAM.unlink(missing_ok=True)

            result = subprocess.run(
                ["bash", str(SCRIPT)], capture_output=True, text=True, timeout=30
            )
            assert result.returncode == 0, (
                f"run_mc.sh failed with exit code {result.returncode}.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            assert marker.exists() and marker.stat().st_size > 0, (
                "run_mc.sh did not execute ncdump."
            )
            assert HISTOGRAM.is_file(), "run_mc.sh did not generate histogram.txt."

            actual = HISTOGRAM.read_text().strip()
            expected = expected_histogram(offset)
            assert actual == expected, (
                f"Histogram produced for base_offset={offset} is incorrect.\n"
                f"Expected:\n{expected}\n\nGot:\n{actual}"
            )
    finally:
        marker.unlink(missing_ok=True)
        ncdump_path.unlink(missing_ok=True)
        if ncdump_backup.exists() or ncdump_backup.is_symlink():
            os.rename(ncdump_backup, ncdump_path)
        EXPERIMENT.write_bytes(original_nc)
        os.chmod(EXPERIMENT, original_mode)


def test_histogram_content():
    """Verify that histogram.txt contains the correct fixed-seed output."""
    expected_output = expected_histogram(12)

    with open(HISTOGRAM, "r") as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, (
        "Contents of /home/user/histogram.txt do not match the expected output.\n"
        f"Expected:\n{expected_output}\n\nGot:\n{actual_output}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
