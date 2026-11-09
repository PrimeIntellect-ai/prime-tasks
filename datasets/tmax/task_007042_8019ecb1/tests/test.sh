#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tarfile
import tempfile


def _expected_lines(path):
    with open(path, 'rb') as f:
        data = f.read()
    assert len(data) % 8 == 0, f"Invalid test binary length: {path}"
    lines = []
    for offset in range(0, len(data), 8):
        record_id, value = struct.unpack_from('<if', data, offset)
        lines.append(f"{record_id},{value:.2f}")
    return lines


def _converter_output(executable, input_path):
    attempts = [
        ([executable, input_path], b''),
        ([executable], open(input_path, 'rb').read()),
    ]
    failures = []
    for command, stdin_data in attempts:
        try:
            result = subprocess.run(
                command,
                input=stdin_data,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            failures.append(str(exc))
            continue
        if result.returncode != 0:
            failures.append(f"exit {result.returncode}: {result.stderr.decode('utf-8', errors='replace')}")
            continue
        try:
            text = result.stdout.decode('utf-8')
        except UnicodeDecodeError as exc:
            failures.append(str(exc))
            continue
        return text.strip().splitlines() if text.strip() else []
    raise AssertionError(f"Could not successfully run {executable}: {'; '.join(failures)}")


def test_converter_c_exists_and_compiled_program_works():
    source = '/home/user/converter.c'
    executable = '/home/user/converter'
    assert os.path.isfile(source), f"Expected C program {source} does not exist."
    assert os.path.isfile(executable), f"Expected compiled program {executable} does not exist."
    assert os.access(executable, os.X_OK), f"Expected compiled program {executable} is not executable."
    with open(executable, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"Expected {executable} to be a compiled ELF executable."

    with tempfile.TemporaryDirectory() as tmp:
        rebuilt = os.path.join(tmp, 'converter_from_source')
        compile_result = subprocess.run(
            ['gcc', source, '-o', rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            check=False,
        )
        assert compile_result.returncode == 0, (
            f"{source} did not compile successfully: "
            f"{compile_result.stderr.decode('utf-8', errors='replace')}"
        )

        fixtures = []
        with tarfile.open('/home/user/raw_sensors.tar.gz', 'r:gz') as tar:
            for name in sorted(m for m in tar.getnames() if m.endswith('.bin')):
                extracted = tar.extractfile(name)
                assert extracted is not None
                path = os.path.join(tmp, os.path.basename(name))
                with open(path, 'wb') as f:
                    f.write(extracted.read())
                fixtures.append(path)
        assert len(fixtures) == 5, "Expected five supplied sensor binaries."

        private_path = os.path.join(tmp, 'private_records.bin')
        rng = secrets.SystemRandom()
        private_records = [
            (rng.randint(-2000000000, 2000000000), rng.choice([1.25, 8.5, 19.75, 240.0])),
            (rng.randint(-2000000000, 2000000000), rng.choice([-1.25, -8.5, -19.75, -240.0])),
            (rng.randint(-2000000000, 2000000000), 0.0),
            (rng.randint(-2000000000, 2000000000), rng.choice([3.25, 14.5, 91.75])),
        ]
        with open(private_path, 'wb') as f:
            for record_id, value in private_records:
                f.write(struct.pack('<if', record_id, value))
        fixtures.append(private_path)

        for program in (rebuilt, executable):
            for fixture in fixtures:
                actual = _converter_output(program, fixture)
                expected = _expected_lines(fixture)
                assert actual == expected, (
                    f"{program} did not correctly convert {os.path.basename(fixture)}. "
                    f"Expected {expected!r}, got {actual!r}."
                )


def test_dataset_csv_content():
    path = '/home/user/dataset.csv'
    assert os.path.isfile(path), f"Expected file {path} does not exist."

    expected_content = (
        "1,100.00\n"
        "3,7.78\n"
        "4,1.23\n"
        "8,42.12\n"
        "10,15.23\n"
        "12,3.14\n"
        "22,5.55\n"
        "25,12.34\n"
        "105,88.88\n"
    )

    with open(path, 'r') as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), f"Content of {path} does not match the expected sorted and filtered output."


def test_clean_dataset_archive():
    archive_path = '/home/user/clean_dataset.tar.gz'
    assert os.path.isfile(archive_path), f"Expected archive {archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"File {archive_path} is not a valid tar archive."

    with tarfile.open(archive_path, 'r:gz') as tar:
        members = tar.getnames()
        csv_members = [m for m in members if m.endswith('dataset.csv')]
        assert csv_members, f"dataset.csv not found in {archive_path}"

        member_name = csv_members[0]
        f = tar.extractfile(member_name)
        assert f is not None, f"Could not extract {member_name} from {archive_path}"
        content = f.read().decode('utf-8')

        expected_content = (
            "1,100.00\n"
            "3,7.78\n"
            "4,1.23\n"
            "8,42.12\n"
            "10,15.23\n"
            "12,3.14\n"
            "22,5.55\n"
            "25,12.34\n"
            "105,88.88\n"
        )

        assert content.strip() == expected_content.strip(), f"Content of archived dataset.csv does not match the expected output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
