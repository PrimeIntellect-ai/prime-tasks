#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tarfile
import tempfile
import uuid

import pytest

REPO = "/home/user/repo"
SCRIPT = os.path.join(REPO, "run_tests.sh")


def test_plugins_extracted():
    plugins_dir = "/home/user/repo/plugins"
    assert os.path.isdir(plugins_dir), f"Directory {plugins_dir} does not exist. Plugins were not extracted correctly."
    assert os.path.isfile(os.path.join(plugins_dir, "plugin_beta.so")), "plugin_beta.so not found in the extracted plugins directory."


def test_run_tests_script_exists_and_executable():
    script_path = "/home/user/repo/run_tests.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."
    assert not os.path.islink(script_path), f"{script_path} must be a bash script, not a symlink."
    with open(script_path, "rb") as f:
        first_line = f.readline()
    assert first_line.startswith(b"#!") and b"bash" in first_line, f"{script_path} does not have a bash shebang."


def test_lib_symlink_correct():
    symlink_path = "/home/user/repo/lib/libprocessor.so"
    assert os.path.islink(symlink_path), f"{symlink_path} does not exist or is not a symlink."

    target = os.readlink(symlink_path)
    abs_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), target))

    expected_target = "/home/user/repo/plugins/plugin_beta.so"
    assert abs_target == expected_target, f"Symlink points to {abs_target}, expected it to resolve to {expected_target}."


def test_output_file_contents():
    output_path = "/home/user/repo/test_output.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    with open(output_path, "r") as f:
        content = f.read().strip()

    expected_content = "INIT_ENGINE\nSUCCESS_DATA_PROCESSED_V2"
    assert content == expected_content, f"Output file content is incorrect. Got:\n{content}\nExpected:\n{expected_content}"


def _compile_shared(source, output):
    source_path = output + ".c"
    with open(source_path, "w") as f:
        f.write(source)
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", output, source_path],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_script_performs_workflow_on_fresh_candidates():
    token = uuid.uuid4().hex
    expected_message = "VERIFIER_" + token
    valid_name = "candidate_" + uuid.uuid4().hex + ".so"
    decoy_names = [
        "candidate_" + uuid.uuid4().hex + ".so",
        "candidate_" + uuid.uuid4().hex + ".so",
    ]

    with tempfile.TemporaryDirectory() as build_dir:
        valid_path = os.path.join(build_dir, valid_name)
        _compile_shared(
            '#include <stdio.h>\nvoid process_record_v2(void) { puts("%s"); }\n' % expected_message,
            valid_path,
        )
        _compile_shared(
            '#include <stdio.h>\nvoid process_record_v1(void) { puts("DECOY_V1"); }\n',
            os.path.join(build_dir, decoy_names[0]),
        )
        _compile_shared(
            '#include <stdio.h>\nvoid process_record_v3(void) { puts("DECOY_V3"); }\n',
            os.path.join(build_dir, decoy_names[1]),
        )

        archive = os.path.join(REPO, "plugins.tar.gz")
        with tarfile.open(archive, "w:gz") as tf:
            for name in [decoy_names[0], valid_name, decoy_names[1]]:
                tf.add(os.path.join(build_dir, name), arcname=name)

        for path in [os.path.join(REPO, "plugins"), os.path.join(REPO, "lib")]:
            if os.path.lexists(path):
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path)
                else:
                    os.unlink(path)
        output_path = os.path.join(REPO, "test_output.txt")
        if os.path.lexists(output_path):
            os.unlink(output_path)

        env = os.environ.copy()
        env.pop("LD_LIBRARY_PATH", None)
        result = subprocess.run(
            [SCRIPT],
            cwd=REPO,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"run_tests.sh failed on a fresh plugin archive.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        symlink_path = os.path.join(REPO, "lib", "libprocessor.so")
        assert os.path.islink(symlink_path), "run_tests.sh did not create lib/libprocessor.so as a symlink."
        resolved_target = os.path.realpath(symlink_path)
        expected_target = os.path.join(REPO, "plugins", valid_name)
        assert resolved_target == expected_target, (
            f"The script selected {resolved_target}, but symbol analysis identifies {expected_target}."
        )

        nm_result = subprocess.run(
            ["nm", "-D", "--defined-only", resolved_target],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert any(
            len(line.split()) >= 3 and line.split()[-2] == "T" and line.split()[-1] == "process_record_v2"
            for line in nm_result.stdout.splitlines()
        ), "Selected library does not export process_record_v2 as a global text symbol."

        assert os.path.isfile(output_path), "run_tests.sh did not generate test_output.txt."
        with open(output_path, "r") as f:
            content = f.read().strip()
        expected = "INIT_ENGINE\n" + expected_message
        assert content == expected, f"Fresh execution output was incorrect. Got:\n{content}\nExpected:\n{expected}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
