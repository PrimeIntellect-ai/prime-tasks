#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import secrets
import subprocess
from pathlib import Path


def test_etl_fixed_executable():
    exe_path = "/home/user/etl_fixed"
    assert os.path.exists(exe_path), f"Missing executable: {exe_path}"
    assert os.path.isfile(exe_path), f"{exe_path} is not a file"
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable"

    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_path} is not a compiled ELF executable"


def test_data_clean_csv():
    clean_csv = "/home/user/data_clean.csv"
    assert os.path.exists(clean_csv), f"Missing file: {clean_csv}"

    with open(clean_csv, "r") as f:
        content = f.read().strip()

    expected_content = """id,timestamp
1,1600000000
2,1600000001
3,3000000000
4,4000000000
5,500000000000"""

    assert content == expected_content, "The content of data_clean.csv does not match the expected output. Large timestamps may still be overflowing."


def test_fixed_source_and_executable_on_generated_inputs(tmp_path):
    source = Path("/home/user/etl.c")
    executable = Path("/home/user/etl_fixed")
    input_path = Path("/home/user/data.csv")
    output_path = Path("/home/user/data_clean.csv")
    rebuilt = tmp_path / "etl_rebuilt"

    assert source.exists() and source.is_file(), "Missing fixed source file: /home/user/etl.c"
    build = subprocess.run(
        ["gcc", str(source), "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f"The submitted etl.c does not compile:\n{build.stderr}"

    original_input = input_path.read_bytes() if input_path.exists() else None
    original_output = output_path.read_bytes() if output_path.exists() else None

    rng = secrets.SystemRandom()
    timestamps = [
        2147483648 + rng.randrange(1, 1000000),
        4294967296 + rng.randrange(1, 1000000),
        rng.randrange(10**10, 10**11),
        rng.randrange(10**11, 10**12),
        10**12,
    ]
    ids = rng.sample(range(10, 1000000), len(timestamps))
    generated_input = "id,timestamp\n" + "".join(
        f"{row_id},{timestamp}\n" for row_id, timestamp in zip(ids, timestamps)
    )
    expected_output = generated_input

    try:
        for program in (executable, rebuilt):
            input_path.write_text(generated_input)
            if output_path.exists():
                output_path.unlink()

            result = subprocess.run(
                [str(program)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"{program} failed on generated large timestamps with exit code "
                f"{result.returncode}: {result.stderr}"
            )
            assert output_path.exists(), f"{program} did not generate /home/user/data_clean.csv"
            assert output_path.read_text() == expected_output, (
                f"{program} corrupted generated timestamps up to 10^12"
            )
    finally:
        if original_input is None:
            input_path.unlink(missing_ok=True)
        else:
            input_path.write_bytes(original_input)
        if original_output is None:
            output_path.unlink(missing_ok=True)
        else:
            output_path.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
