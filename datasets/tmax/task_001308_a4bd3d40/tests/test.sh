#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

HOME_DIR = "/home/user"
ETL_PROCESSOR_C = os.path.join(HOME_DIR, "etl_processor.c")
MAKEFILE = os.path.join(HOME_DIR, "Makefile")
TEST_PIPELINE = os.path.join(HOME_DIR, "test_pipeline.sh")
RAW_DATA = os.path.join(HOME_DIR, "raw_data.csv")
CLEAN_DATA = os.path.join(HOME_DIR, "clean_data.csv")
REJECTED_LOG = os.path.join(HOME_DIR, "rejected.log")
EXECUTABLE = os.path.join(HOME_DIR, "etl_processor")


def run(command, **kwargs):
    return subprocess.run(
        command,
        cwd=HOME_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        **kwargs
    )


def test_files_exist():
    assert os.path.isfile(ETL_PROCESSOR_C), f"Missing {ETL_PROCESSOR_C}"
    assert os.path.isfile(MAKEFILE), f"Missing {MAKEFILE}"
    assert os.path.isfile(TEST_PIPELINE), f"Missing {TEST_PIPELINE}"


def test_pipeline_script_executable():
    assert os.access(TEST_PIPELINE, os.X_OK), f"{TEST_PIPELINE} is not executable"


def test_pipeline_execution():
    result = run([TEST_PIPELINE])
    assert result.returncode == 0, (
        f"test_pipeline.sh failed with exit code {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    assert "REPRODUCIBLE" in result.stdout, (
        "test_pipeline.sh did not print 'REPRODUCIBLE'"
    )


def test_data_outputs():
    assert os.path.isfile(CLEAN_DATA), f"Missing {CLEAN_DATA} after running pipeline"
    assert os.path.isfile(REJECTED_LOG), f"Missing {REJECTED_LOG} after running pipeline"

    expected_clean = [
        "1,ACTIVE,10.50",
        "4,INACTIVE,5.50",
        "6,ACTIVE,100.00"
    ]
    expected_rejected = [
        "-2,ACTIVE,15.0",
        "3,UNKNOWN,20.0",
        "invalid,ACTIVE,1.0",
        "5,ACTIVE,badfloat"
    ]

    with open(CLEAN_DATA, "r") as f:
        clean_lines = [line.strip() for line in f if line.strip()]
    with open(REJECTED_LOG, "r") as f:
        rejected_lines = [line.strip() for line in f if line.strip()]

    assert clean_lines == expected_clean, (
        f"clean_data.csv contents mismatch. Got: {clean_lines}"
    )
    assert rejected_lines == expected_rejected, (
        f"rejected.log contents mismatch. Got: {rejected_lines}"
    )


def test_makefile_build_and_required_flags():
    clean = run(["make", "clean"])
    assert clean.returncode == 0, f"make clean failed. stderr: {clean.stderr}"

    dry_all = run(["make", "-n", "all"])
    assert dry_all.returncode == 0, f"Makefile has no working all target: {dry_all.stderr}"
    compiler_lines = [
        line for line in (dry_all.stdout + "\n" + dry_all.stderr).splitlines()
        if re.search(r"(^|[/\s])gcc(\s|$)", line)
    ]
    assert compiler_lines, "The all target does not invoke gcc"
    assert any("-O2" in line and "-Wall" in line for line in compiler_lines), (
        "The gcc command in the all target must include both -O2 and -Wall"
    )

    build = run(["make"])
    assert build.returncode == 0, f"default make failed. stderr: {build.stderr}"
    assert os.path.isfile(EXECUTABLE), "default make did not create etl_processor"
    assert os.access(EXECUTABLE, os.X_OK), "etl_processor is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "etl_processor is not a compiled ELF executable"


def randomized_fixture():
    first = secrets.randbelow(800000) + 100000
    second = first + 1000001
    invalid_id = second + 1000001
    raw = (
        f"{first},ACTIVE,10.25\n"
        "0,ACTIVE,9.0\n"
        f"{invalid_id},UNKNOWN,1.0\n"
        f"{invalid_id},ACTIVE,2.0junk\n"
        f"{invalid_id},INACTIVE,3.0,extra\n"
        f"{invalid_id},ACTIVE\n"
        "\n"
        f"{second},INACTIVE,-7.50\n"
        f"x{invalid_id},ACTIVE,4.0"
    ).encode()
    clean = (
        f"{first},ACTIVE,10.25\n"
        f"{second},INACTIVE,-7.50\n"
    ).encode()
    rejected = (
        "0,ACTIVE,9.0\n"
        f"{invalid_id},UNKNOWN,1.0\n"
        f"{invalid_id},ACTIVE,2.0junk\n"
        f"{invalid_id},INACTIVE,3.0,extra\n"
        f"{invalid_id},ACTIVE\n"
        "\n"
        f"x{invalid_id},ACTIVE,4.0"
    ).encode()
    return raw, clean, rejected


def test_processor_on_changed_input():
    with open(RAW_DATA, "rb") as f:
        original = f.read()
    raw, expected_clean, expected_rejected = randomized_fixture()
    try:
        with open(RAW_DATA, "wb") as f:
            f.write(raw)

        clean = run(["make", "clean"])
        assert clean.returncode == 0, clean.stderr
        build = run(["make"])
        assert build.returncode == 0, build.stderr
        result = run([EXECUTABLE])
        assert result.returncode == 0, f"etl_processor failed: {result.stderr}"

        with open(CLEAN_DATA, "rb") as f:
            actual_clean = f.read()
        with open(REJECTED_LOG, "rb") as f:
            actual_rejected = f.read()
        assert actual_clean == expected_clean, (
            f"changed-input clean output mismatch: {actual_clean!r}"
        )
        assert actual_rejected == expected_rejected, (
            f"changed-input rejected output mismatch: {actual_rejected!r}"
        )
    finally:
        with open(RAW_DATA, "wb") as f:
            f.write(original)


def test_reproducibility_script_runs_required_steps_on_changed_input():
    with open(RAW_DATA, "rb") as f:
        original = f.read()
    raw, expected_clean, expected_rejected = randomized_fixture()
    try:
        with open(RAW_DATA, "wb") as f:
            f.write(raw)

        result = run(["bash", "-x", TEST_PIPELINE])
        assert result.returncode == 0, (
            f"test_pipeline.sh failed on changed input: {result.stderr}"
        )
        assert "REPRODUCIBLE" in result.stdout

        trace = [line.lstrip("+ ").strip() for line in result.stderr.splitlines()]
        assert sum(line == "make clean" for line in trace) >= 2, (
            "test_pipeline.sh did not execute make clean twice"
        )
        assert sum(line == "make" for line in trace) >= 2, (
            "test_pipeline.sh did not execute make twice"
        )
        assert sum(line in ("./etl_processor", EXECUTABLE) for line in trace) >= 2, (
            "test_pipeline.sh did not execute etl_processor twice"
        )
        assert sum(re.search(r"(^|/)md5sum\s", line) is not None or
                   line.startswith("md5sum ") for line in trace) >= 2, (
            "test_pipeline.sh did not compute md5sum twice"
        )

        with open(CLEAN_DATA, "rb") as f:
            assert f.read() == expected_clean
        with open(REJECTED_LOG, "rb") as f:
            assert f.read() == expected_rejected
    finally:
        with open(RAW_DATA, "wb") as f:
            f.write(original)


def test_makefile_clean():
    result = run(["make", "clean"])
    assert result.returncode == 0, f"make clean failed. stderr: {result.stderr}"
    assert not os.path.exists(CLEAN_DATA), f"make clean did not remove {CLEAN_DATA}"
    assert not os.path.exists(REJECTED_LOG), f"make clean did not remove {REJECTED_LOG}"
    assert not os.path.exists(EXECUTABLE), f"make clean did not remove {EXECUTABLE}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
