#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import shutil
import stat
import subprocess
import tempfile

PACKAGE = "/home/user/grpc-math-service/package.sh"
ORCHESTRATOR = "/home/user/test_orchestrator.sh"
PROJECT = "/home/user/grpc-math-service"
A_CONTENT = b'syntax = "proto3"; message AddRequest { int32 a = 1; int32 b = 2; }'
B_CONTENT = b'syntax = "proto3"; message SubRequest { int32 a = 1; int32 b = 2; }'


def encoded_checksum(data):
    digest_hex = hashlib.sha256(data).hexdigest().encode("ascii")
    return base64.b64encode(digest_hex)


def clear_orchestrator_outputs():
    for path in [
        "/home/user/test_result.log",
        "/home/user/manifest_hash.txt",
        os.path.join(PROJECT, "manifest_hash.txt"),
    ]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    for path in ["/home/user/build", os.path.join(PROJECT, "build")]:
        shutil.rmtree(path, ignore_errors=True)


def run_orchestrator():
    return subprocess.run(
        [ORCHESTRATOR], cwd=PROJECT, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=20
    )


def test_package_sh_fixed():
    assert os.path.isfile(PACKAGE), f"File {PACKAGE} does not exist."
    with open(PACKAGE, "r") as f:
        content = f.read()
    assert "sort" in content, "package.sh does not appear to sort the files. Use 'sort' in the pipeline."


def test_package_sh_behavior():
    with tempfile.TemporaryDirectory() as work:
        protos = os.path.join(work, "protos")
        os.mkdir(protos)
        # Deliberately create files in reverse alphabetical order.
        with open(os.path.join(protos, "z_last.proto"), "wb") as f:
            f.write(b"LAST")
        with open(os.path.join(protos, "m_middle.proto"), "wb") as f:
            f.write(b"MIDDLE")
        with open(os.path.join(protos, "a_first.proto"), "wb") as f:
            f.write(b"FIRST")

        result = subprocess.run(
            [PACKAGE, protos], cwd=work, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=20
        )
        assert result.returncode == 0, result.stderr.decode(errors="replace")

        expected_bundle = b"FIRSTMIDDLELAST"
        with open(os.path.join(work, "build", "bundle.proto"), "rb") as f:
            assert f.read() == expected_bundle, "bundle.proto is not concatenated in alphabetical filename order"

        manifest_path = os.path.join(work, "manifest_hash.txt")
        assert os.path.isfile(manifest_path), "package.sh did not create manifest_hash.txt"
        with open(manifest_path, "rb") as f:
            manifest = f.read()
        assert manifest == encoded_checksum(expected_bundle), "manifest checksum is incorrect or contains a newline"
        assert not manifest.endswith(b"\n"), "manifest_hash.txt still contains a trailing newline."


def test_test_orchestrator_exists_and_executable():
    assert os.path.isfile(ORCHESTRATOR), f"File {ORCHESTRATOR} does not exist."
    st = os.stat(ORCHESTRATOR)
    assert bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH), f"File {ORCHESTRATOR} is not executable."


def test_orchestrator_end_to_end_and_failure_detection():
    shutil.rmtree("/home/user/mock_protos", ignore_errors=True)
    clear_orchestrator_outputs()

    with tempfile.TemporaryDirectory() as temp:
        saved = os.path.join(temp, "package.sh")
        shutil.copy2(PACKAGE, saved)
        marker = os.path.join(temp, "invocation")

        try:
            # Trace that the orchestrator really invokes package.sh with the fixture directory.
            with open(PACKAGE, "w") as f:
                f.write("#!/bin/bash\n")
                f.write("printf '%s\\n' \"$@\" > " + repr(marker) + "\n")
                f.write("exec " + repr(saved) + " \"$@\"\n")
            os.chmod(PACKAGE, 0o755)

            result = run_orchestrator()
            assert result.returncode == 0, result.stderr.decode(errors="replace")
            assert os.path.isfile(marker), "test_orchestrator.sh did not execute package.sh"
            with open(marker, "r") as f:
                args = f.read().splitlines()
            assert args == ["/home/user/mock_protos"], "package.sh was not passed /home/user/mock_protos as its target"
            with open("/home/user/test_result.log", "r") as f:
                assert f.read().strip() == "PASS", "A correct package result did not produce PASS"

            # A fabricated, unconditional PASS must not be accepted: make package.sh
            # generate a bad checksum and require the orchestrator to report FAIL.
            clear_orchestrator_outputs()
            with open(PACKAGE, "w") as f:
                f.write("#!/bin/bash\nmkdir -p build\nprintf 'bad bundle' > build/bundle.proto\nprintf 'WRONG' > manifest_hash.txt\n")
            os.chmod(PACKAGE, 0o755)
            run_orchestrator()
            assert os.path.isfile("/home/user/test_result.log"), "Orchestrator did not write test_result.log on checksum mismatch"
            with open("/home/user/test_result.log", "r") as f:
                assert f.read().strip() == "FAIL", "Orchestrator self-reports PASS even when package.sh generates a wrong checksum"
        finally:
            shutil.copy2(saved, PACKAGE)

    # Leave the requested final state produced by the real repaired package script.
    clear_orchestrator_outputs()
    result = run_orchestrator()
    assert result.returncode == 0, result.stderr.decode(errors="replace")

    a_path = "/home/user/mock_protos/a_math.proto"
    b_path = "/home/user/mock_protos/b_math.proto"
    assert os.path.isfile(a_path), f"File {a_path} does not exist."
    assert os.path.isfile(b_path), f"File {b_path} does not exist."
    with open(a_path, "rb") as f:
        a_data = f.read()
    with open(b_path, "rb") as f:
        b_data = f.read()
    assert a_data in (A_CONTENT, A_CONTENT + b"\n"), "a_math.proto does not have the required content"
    assert b_data in (B_CONTENT, B_CONTENT + b"\n"), "b_math.proto does not have the required content"

    expected = encoded_checksum(a_data + b_data)
    manifests = [
        p for p in [os.path.join(PROJECT, "manifest_hash.txt"), "/home/user/manifest_hash.txt"]
        if os.path.isfile(p)
    ]
    assert manifests, "The orchestrator/package script did not generate manifest_hash.txt"
    assert any(open(p, "rb").read() == expected for p in manifests), "Generated manifest does not match the sorted fixture bundle checksum"


def test_mock_protos_created():
    assert os.path.isfile("/home/user/mock_protos/a_math.proto"), "File /home/user/mock_protos/a_math.proto does not exist."
    assert os.path.isfile("/home/user/mock_protos/b_math.proto"), "File /home/user/mock_protos/b_math.proto does not exist."


def test_test_result_log_pass():
    path = "/home/user/test_result.log"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "PASS", f"Expected 'PASS' in {path}, but got '{content}'"


def test_manifest_hash_no_newline():
    path = "/home/user/grpc-math-service/manifest_hash.txt"
    if os.path.isfile(path):
        with open(path, "rb") as f:
            content = f.read()
        if len(content) > 0:
            assert content[-1:] != b"\n", "manifest_hash.txt still contains a trailing newline."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
