#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.request
import uuid

import pytest
import redis

SANITIZER_PATH = "/home/user/sanitizer/elf_sanitizer"
SOURCE_PATH = "/home/user/sanitizer/elf_sanitizer.cpp"
CLEAN_CORPUS = "/home/user/corpora/clean"
EVIL_CORPUS = "/home/user/corpora/evil"
STAGING = "/home/user/staging"


def run_sanitizer(executable, directory):
    return subprocess.run(
        [executable, directory], capture_output=True, timeout=10
    ).returncode


def make_elf(output_path, gcode=None):
    work = os.path.dirname(output_path)
    source = os.path.join(work, uuid.uuid4().hex + ".c")
    base = os.path.join(work, uuid.uuid4().hex + ".bin")
    with open(source, "w", encoding="utf-8") as f:
        f.write("int main(void) { return 0; }\n")
    subprocess.run(["gcc", source, "-o", base], check=True, capture_output=True)
    if gcode is None:
        shutil.copy2(base, output_path)
    else:
        payload = os.path.join(work, uuid.uuid4().hex + ".txt")
        with open(payload, "w", encoding="utf-8") as f:
            f.write(gcode)
        subprocess.run(
            ["objcopy", "--add-section", f".cnc_gcode={payload}", base, output_path],
            check=True,
            capture_output=True,
        )


def exercise_generated_cases(executable):
    cases = [
        (None, 0),
        ("G0 X1 Y2 Z0.0\nG1 X2 Y3 Z4.25\n", 0),
        ("G1 X10 Y20 Z-0.125\n", 1),
        ("G0 Z-3.5 X7\n", 1),
    ]
    for payload, expected in cases:
        with tempfile.TemporaryDirectory() as directory:
            artifact = os.path.join(directory, uuid.uuid4().hex + ".elf")
            make_elf(artifact, payload)
            actual = run_sanitizer(executable, directory)
            assert actual == expected, (
                f"Generated ELF expected exit {expected}, got {actual}"
            )

    with tempfile.TemporaryDirectory() as directory:
        nested = os.path.join(directory, uuid.uuid4().hex, uuid.uuid4().hex)
        os.makedirs(nested)
        make_elf(
            os.path.join(nested, uuid.uuid4().hex + ".elf"),
            "G1 X5 Z2.0\n",
        )
        assert run_sanitizer(executable, directory) == 0
        make_elf(
            os.path.join(nested, uuid.uuid4().hex + ".elf"),
            "G1 Y8 Z-1.75\n",
        )
        assert run_sanitizer(executable, directory) == 1


def test_sanitizer_binary_exists():
    assert os.path.isfile(SANITIZER_PATH), f"Sanitizer binary not found at {SANITIZER_PATH}"
    assert os.access(SANITIZER_PATH, os.X_OK), f"Sanitizer binary at {SANITIZER_PATH} is not executable"
    with open(SANITIZER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer executable is not an ELF binary"


def test_cpp_source_exists_compiles_and_works():
    assert os.path.isfile(SOURCE_PATH), f"C++ source not found at {SOURCE_PATH}"
    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "rebuilt_sanitizer")
        result = subprocess.run(
            ["g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"C++ source failed to compile: {result.stderr}"
        exercise_generated_cases(rebuilt)


def test_sanitizer_adversarial_corpus():
    evil_files = [f for f in os.listdir(EVIL_CORPUS) if f.endswith('.elf')]
    clean_files = [f for f in os.listdir(CLEAN_CORPUS) if f.endswith('.elf')]

    assert len(evil_files) > 0, "No evil ELF files found in corpus"
    assert len(clean_files) > 0, "No clean ELF files found in corpus"

    evil_bypassed = []
    clean_modified = []

    for ef in evil_files:
        with tempfile.TemporaryDirectory() as tmpdir:
            shutil.copy(os.path.join(EVIL_CORPUS, ef), tmpdir)
            if run_sanitizer(SANITIZER_PATH, tmpdir) != 1:
                evil_bypassed.append(ef)

    for cf in clean_files:
        with tempfile.TemporaryDirectory() as tmpdir:
            shutil.copy(os.path.join(CLEAN_CORPUS, cf), tmpdir)
            if run_sanitizer(SANITIZER_PATH, tmpdir) != 0:
                clean_modified.append(cf)

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed[:5])}")
    if clean_modified:
        error_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified[:5])}")
    if error_msg:
        pytest.fail(" | ".join(error_msg))


def test_sanitizer_generated_randomized_elfs():
    exercise_generated_cases(SANITIZER_PATH)


def upload_file(filepath):
    url = "http://localhost:8080/upload"
    with open(filepath, "rb") as f:
        file_data = f.read()

    boundary = "----VerifierBoundary" + uuid.uuid4().hex
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{os.path.basename(filepath)}"\r\n'
        f"Content-Type: application/octet-stream\r\n\r\n"
    ).encode("utf-8") + file_data + f"\r\n--{boundary}--\r\n".encode("utf-8")

    req = urllib.request.Request(url, data=body)
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return response.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception as e:
        pytest.fail(f"HTTP Request failed: {e}")


def test_end_to_end_api_redis_deletion_and_invocation():
    client = redis.Redis(host="localhost", port=6379, db=0)
    client.ping()
    client.flushdb()

    os.makedirs(STAGING, exist_ok=True)
    for entry in os.listdir(STAGING):
        path = os.path.join(STAGING, entry)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    token = uuid.uuid4().hex
    saved_binary = SANITIZER_PATH + ".verifier-real-" + token
    marker = "/tmp/sanitizer-invocations-" + token

    with tempfile.TemporaryDirectory() as directory:
        clean_file = os.path.join(directory, uuid.uuid4().hex + ".elf")
        evil_file = os.path.join(directory, uuid.uuid4().hex + ".elf")
        make_elf(clean_file, "G0 X2 Z0.0\nG1 Y4 Z6.5\n")
        make_elf(evil_file, "G1 X9 Y3 Z-2.25\n")
        clean_name = os.path.basename(clean_file)
        evil_name = os.path.basename(evil_file)

        os.replace(SANITIZER_PATH, saved_binary)
        try:
            with open(SANITIZER_PATH, "w", encoding="utf-8") as f:
                f.write(
                    "#!/bin/sh\n"
                    f"echo invoked >> {shlex.quote(marker)}\n"
                    f"exec {shlex.quote(saved_binary)} \"$@\"\n"
                )
            os.chmod(SANITIZER_PATH, 0o755)

            clean_status = upload_file(clean_file)
            evil_status = upload_file(evil_file)
        finally:
            if os.path.lexists(SANITIZER_PATH):
                os.unlink(SANITIZER_PATH)
            os.replace(saved_binary, SANITIZER_PATH)

        assert clean_status == 200, f"Clean file upload failed, expected HTTP 200 but got {clean_status}"
        assert evil_status == 403, f"Evil file upload bypassed, expected HTTP 403 but got {evil_status}"
        assert os.path.isfile(marker), "Flask API did not invoke the configured sanitizer"
        with open(marker, "r", encoding="utf-8") as f:
            assert len(f.readlines()) >= 2, "Sanitizer was not invoked for both uploads"
        os.unlink(marker)

        assert os.path.isfile(os.path.join(STAGING, clean_name)), "Accepted clean upload was not retained"
        assert not os.path.exists(os.path.join(STAGING, evil_name)), "Rejected evil upload was not deleted"
        assert client.get(clean_name) is not None, "Clean artifact was not registered in Redis"
        assert client.get(evil_name) is None, "Evil artifact was registered in Redis"
        assert set(client.keys("*")) == {clean_name.encode()}, "Redis contains artifacts other than the accepted clean upload"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
