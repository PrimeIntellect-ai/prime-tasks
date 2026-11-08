#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
import uuid


def test_c_program_exists():
    assert os.path.isfile('/home/user/project/organizer.c'), "The C source code '/home/user/project/organizer.c' does not exist."


def test_compiled_program_exists():
    assert os.path.isfile('/home/user/project/organizer'), "The compiled program '/home/user/project/organizer' does not exist."
    assert os.access('/home/user/project/organizer', os.X_OK), "The compiled program '/home/user/project/organizer' is not executable."
    with open('/home/user/project/organizer', 'rb') as f:
        assert f.read(4) == b'\x7fELF', "The compiled program is not an ELF executable."


def test_target_directories_exist():
    dirs = [
        '/home/user/project/organized/textures',
        '/home/user/project/organized/objects',
        '/home/user/project/organized/archives'
    ]
    for d in dirs:
        assert os.path.isdir(d), f"Target directory '{d}' does not exist."


def test_files_moved_correctly():
    expected_files = {
        '/home/user/project/organized/textures/file_a.dat': b'\x89\x50\x4e\x47',
        '/home/user/project/organized/objects/file_b.dat': b'\xca\xfe\xba\xbe',
        '/home/user/project/organized/archives/file_c.dat': b'\x50\x4b\x03\x04',
        '/home/user/project/organized/textures/file_d.dat': b'\x89\x50\x4e\x47',
        '/home/user/project/dump/file_unknown.dat': b'\x00\x00\x00\x00'
    }

    for path, magic in expected_files.items():
        assert os.path.isfile(path), f"Expected file '{path}' is missing."
        with open(path, 'rb') as f:
            content = f.read(4)
            assert content.lower() == magic.lower(), f"File '{path}' has incorrect magic bytes."


def test_files_removed_from_dump():
    unexpected_files = [
        '/home/user/project/dump/file_a.dat',
        '/home/user/project/dump/file_b.dat',
        '/home/user/project/dump/file_c.dat',
        '/home/user/project/dump/file_d.dat'
    ]
    for path in unexpected_files:
        assert not os.path.exists(path), f"File '{path}' should have been moved out of the dump directory."


def _exercise_program(program, config, input_paths, expected_output):
    result = subprocess.run(
        [program, config],
        input=''.join(path + '\n' for path in input_paths),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, f"Organizer failed: {result.stderr}"
    assert result.stdout == expected_output, (
        f"Organizer produced incorrect commands. Expected {expected_output!r}, "
        f"got {result.stdout!r}."
    )

    no_arg = subprocess.run(
        [program], input='', text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=5
    )
    assert no_arg.returncode != 0, "Organizer must reject invocation without a configuration argument."

    extra_arg = subprocess.run(
        [program, config, config], input='', text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=5
    )
    assert extra_arg.returncode != 0, "Organizer must reject invocation with more than one argument."


def test_source_and_executable_are_configuration_driven():
    with tempfile.TemporaryDirectory(prefix='organizer_test_') as td:
        rebuilt = os.path.join(td, 'rebuilt_organizer')
        build = subprocess.run(
            ['gcc', '/home/user/project/organizer.c', '-o', rebuilt],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert build.returncode == 0, f"organizer.c does not compile with gcc: {build.stderr}"

        magics = []
        while len(magics) < 3:
            value = os.urandom(4)
            if value not in magics:
                magics.append(value)

        targets = ['textures', 'objects', 'archives']
        random.SystemRandom().shuffle(targets)
        config = os.path.join(td, 'dynamic_magic.conf')
        with open(config, 'w', encoding='ascii') as f:
            for magic, target in zip(magics, targets):
                f.write(f"{magic.hex()}:{target}\n")

        token = uuid.uuid4().hex
        matched_paths = []
        for index, magic in enumerate(magics):
            path = os.path.join(td, f'{token}_{index}.bin')
            with open(path, 'wb') as f:
                f.write(magic + os.urandom(7))
            matched_paths.append(path)

        duplicate_path = os.path.join(td, f'{token}_duplicate.bin')
        with open(duplicate_path, 'wb') as f:
            f.write(magics[0] + b'duplicate')

        unknown_magic = os.urandom(4)
        while unknown_magic in magics:
            unknown_magic = os.urandom(4)
        unknown_path = os.path.join(td, f'{token}_unknown.bin')
        with open(unknown_path, 'wb') as f:
            f.write(unknown_magic + b'unknown')

        short_path = os.path.join(td, f'{token}_short.bin')
        with open(short_path, 'wb') as f:
            f.write(b'abc')

        input_paths = matched_paths + [unknown_path, duplicate_path, short_path]
        expected_lines = []
        for path, target in zip(matched_paths, targets):
            expected_lines.append(f"mv '{path}' '/home/user/project/organized/{target}/'\n")
        expected_lines.append(
            f"mv '{duplicate_path}' '/home/user/project/organized/{targets[0]}/'\n"
        )
        expected_output = ''.join(expected_lines)

        _exercise_program('/home/user/project/organizer', config, input_paths, expected_output)
        _exercise_program(rebuilt, config, input_paths, expected_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
