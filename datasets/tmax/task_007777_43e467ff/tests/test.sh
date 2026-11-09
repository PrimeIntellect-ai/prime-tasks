#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import struct
import subprocess
import tarfile
import tempfile
from pathlib import Path


def get_expected_data():
    records = [
        ("rec_001", 104, 1680000000, [1.1111, 2.2222, 3.3333, 4.4444, 5.5555, 6.6666, 7.7777, 8.8888, 9.9999, 10.0000]),
        ("rec_002", 205, 1680003600, [0.0, -1.5, 3.1415, 2.7182, 42.0, 7.0, 8.0, 9.0, 10.1234, -5.5555]),
        ("rec_003", 99, 1680007200, [100.1, 200.2, 300.3, 400.4, 500.5, 600.6, 700.7, 800.8, 900.9, 1000.1]),
    ]
    expected = {}
    for name, sensor_id, ts, floats in records:
        packed = struct.pack("<10f", *floats)
        unpacked = struct.unpack("<10f", packed)
        csv_line = ",".join(f"{v:.4f}" for v in unpacked)
        expected[name] = {
            "sensor_id": sensor_id,
            "ts": ts,
            "csv_line": csv_line,
            "txt_content": f"Notes for {name}\n",
            "base_name": f"sensor_{sensor_id}_{ts}",
        }
    return expected


def test_conversion_log():
    log_path = "/home/user/conversion.log"
    assert os.path.isfile(log_path), f"Missing log file: {log_path}"

    expected_data = get_expected_data()
    expected_lines = []
    for rec_name in sorted(expected_data.keys()):
        base_name = expected_data[rec_name]["base_name"]
        expected_lines.append(f"{rec_name} -> {base_name}\n")

    with open(log_path, "r") as f:
        lines = f.readlines()

    assert lines == expected_lines, f"Log file contents do not match expected format or sorting. Found: {lines}"


def test_clean_dataset_tarball():
    tarball_path = "/home/user/clean_dataset.tar.gz"
    assert os.path.isfile(tarball_path), f"Missing clean dataset tarball: {tarball_path}"

    expected_data = get_expected_data()

    try:
        with tarfile.open(tarball_path, "r:gz") as tar:
            members = tar.getnames()

            for rec_name, data in expected_data.items():
                base_name = data["base_name"]
                csv_name = f"clean_data/{base_name}.csv"
                txt_name = f"clean_data/{base_name}.txt"

                csv_found = any(m.endswith(csv_name) for m in members)
                txt_found = any(m.endswith(txt_name) for m in members)

                assert csv_found, f"Missing {csv_name} in tarball"
                assert txt_found, f"Missing {txt_name} in tarball"

                csv_member = next(m for m in tar.getmembers() if m.name.endswith(csv_name))
                with tar.extractfile(csv_member) as f:
                    csv_content = f.read().decode("utf-8").strip()
                    assert csv_content == data["csv_line"], f"CSV content mismatch in {csv_name}. Expected: {data['csv_line']}, Got: {csv_content}"

                txt_member = next(m for m in tar.getmembers() if m.name.endswith(txt_name))
                with tar.extractfile(txt_member) as f:
                    txt_content = f.read().decode("utf-8")
                    assert txt_content == data["txt_content"], f"TXT content mismatch in {txt_name}."

    except tarfile.ReadError:
        assert False, f"{tarball_path} is not a valid gzip-compressed tarball"


def test_clean_data_directory():
    clean_dir = Path("/home/user/clean_data")
    assert clean_dir.is_dir(), f"Missing output directory: {clean_dir}"

    for rec_name, data in get_expected_data().items():
        csv_path = clean_dir / f"{data['base_name']}.csv"
        txt_path = clean_dir / f"{data['base_name']}.txt"
        assert csv_path.is_file(), f"Missing generated CSV: {csv_path}"
        assert txt_path.is_file(), f"Missing copied notes file: {txt_path}"
        assert csv_path.read_text().strip() == data["csv_line"]
        assert txt_path.read_text() == data["txt_content"]


def test_process_c_compiles_and_parses_unseen_record():
    source = Path("/home/user/process.c")
    assert source.is_file(), f"Missing C source file: {source}"

    with tempfile.TemporaryDirectory() as build_dir:
        executable = Path(build_dir) / "process_test"
        compiled = subprocess.run(
            ["gcc", "-std=c11", "-O2", str(source), "-lm", "-o", str(executable)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert compiled.returncode == 0, f"process.c does not compile with GCC:\n{compiled.stderr}"

        sensor_id = secrets.randbelow(3000000000) + 100000000
        timestamp = secrets.randbelow(1000000000) + 2000000000
        quarters = [secrets.randbelow(8001) - 4000 for _ in range(10)]
        values = [q / 4.0 for q in quarters]
        expected_csv = ",".join(f"{v:.4f}" for v in values)
        blob = b"SNSR" + struct.pack("<II10f", sensor_id, timestamp, *values)

        succeeded = False
        diagnostics = []
        for mode in ("input_output", "input", "input_directory", "batch"):
            with tempfile.TemporaryDirectory() as run_dir:
                run_path = Path(run_dir)
                dat_path = run_path / "rec_probe.dat"
                dat_path.write_bytes(blob)
                (run_path / "rec_probe.txt").write_text("probe notes\n")
                output_path = run_path / "probe.csv"
                output_dir = run_path / "output"
                output_dir.mkdir()

                if mode == "input_output":
                    command = [str(executable), str(dat_path), str(output_path)]
                elif mode == "input":
                    command = [str(executable), str(dat_path)]
                elif mode == "input_directory":
                    command = [str(executable), str(dat_path), str(output_dir)]
                else:
                    command = [str(executable)]

                try:
                    result = subprocess.run(
                        command,
                        cwd=run_dir,
                        input=blob,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        timeout=5,
                    )
                except (subprocess.TimeoutExpired, OSError) as exc:
                    diagnostics.append(f"{mode}: {exc}")
                    continue

                corpus = result.stdout.decode("utf-8", "replace") + "\n" + result.stderr.decode("utf-8", "replace")
                for item in run_path.rglob("*"):
                    if item.is_file() and item not in (dat_path, run_path / "rec_probe.txt"):
                        corpus += "\n" + str(item.relative_to(run_path))
                        corpus += "\n" + item.read_bytes().decode("utf-8", "replace")

                has_id = re.search(rf"(?<!\d){sensor_id}(?!\d)", corpus) is not None
                has_timestamp = re.search(rf"(?<!\d){timestamp}(?!\d)", corpus) is not None
                has_csv = expected_csv in corpus
                if result.returncode == 0 and has_id and has_timestamp and has_csv:
                    succeeded = True
                    break
                diagnostics.append(
                    f"{mode}: exit={result.returncode}, id={has_id}, timestamp={has_timestamp}, csv={has_csv}"
                )

        assert succeeded, "Compiled process.c did not parse an unseen valid SNSR record. " + "; ".join(diagnostics)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
