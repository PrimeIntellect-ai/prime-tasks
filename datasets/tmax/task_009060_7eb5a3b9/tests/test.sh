#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import shutil
import subprocess
import tempfile
import uuid
import pytest

BIN_PATH = "/home/user/bin/score_seq"
SOURCE_PATH = "/home/user/src/score_seq.c"
SCRIPT_PATH = "/home/user/run_pipeline.sh"
SEQ_DIR = "/home/user/seq_data"
OUTPUT_PATH = "/home/user/reproducible_output.txt"


def compile_reference(path):
    try:
        subprocess.run(
            ["gcc", SOURCE_PATH, "-o", path],
            check=True,
            capture_output=True,
            timeout=30,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to compile the C source code for verification. Error: {e.stderr.decode()}")


def run_binary(path, input_data):
    try:
        return subprocess.run(
            [path],
            input=input_data.encode(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
            timeout=10,
        ).stdout.decode()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        pytest.fail(f"Failed to run {path}: {e}")


def expected_for_current_data(reference_binary):
    files = sorted(
        os.path.join(SEQ_DIR, name)
        for name in os.listdir(SEQ_DIR)
        if name.endswith(".dat")
    )
    input_data = "\n".join(files) + ("\n" if files else "")
    return run_binary(reference_binary, input_data).strip()


def test_binary_exists_and_executable():
    bin_path = BIN_PATH
    assert os.path.exists(bin_path), f"Executable {bin_path} does not exist."
    assert os.path.isfile(bin_path), f"Path {bin_path} is not a file."
    assert os.access(bin_path, os.X_OK), f"File {bin_path} is not executable."

    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{bin_path} is not an ELF executable."

    with tempfile.TemporaryDirectory() as td:
        reference = os.path.join(td, "reference_score_seq")
        compile_reference(reference)

        # A normal gcc build of the provided source is deterministic in this image.
        with open(bin_path, "rb") as f:
            submitted_bytes = f.read()
        with open(reference, "rb") as f:
            reference_bytes = f.read()
        assert submitted_bytes == reference_bytes, (
            f"{bin_path} is not the executable produced by standard gcc from {SOURCE_PATH}."
        )

        # Independently execute both programs on verifier-created paths and data.
        data_dir = os.path.join(td, "inputs_" + uuid.uuid4().hex)
        os.mkdir(data_dir)
        test_values = [
            ("zeta.dat", "-10000000000000000\n"),
            ("alpha.dat", "10000000000000000\n"),
            ("middle.dat", "1.0\n"),
            ("small.dat", "0.000000000000123\n"),
        ]
        paths = []
        for name, value in test_values:
            path = os.path.join(data_dir, name)
            with open(path, "w") as f:
                f.write(value)
            paths.append(path)
        paths.append(os.path.join(data_dir, "missing.dat"))
        input_data = "\n".join(paths) + "\n"
        assert run_binary(bin_path, input_data) == run_binary(reference, input_data), (
            f"{bin_path} does not behave like the program compiled from {SOURCE_PATH}."
        )


def test_script_fixed():
    script_path = SCRIPT_PATH
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    with open(script_path, "r") as f:
        content = f.read()

    assert "sort" in content, f"Script {script_path} does not contain 'sort' command."
    assert "/home/user/bin/score_seq" in content, f"Script {script_path} does not call the expected binary path."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."
    subprocess.run(["bash", "-n", script_path], check=True, timeout=10)

    # Replace the required binary temporarily with a probe. This proves that the
    # runnable script actually invokes that exact path, pipes sorted paths to it,
    # and relays its standard output rather than merely mentioning commands in comments.
    suffix = uuid.uuid4().hex
    data_backup = f"/home/user/.seq_data_backup_{suffix}"
    binary_backup = f"/home/user/bin/.score_seq_backup_{suffix}"
    capture_path = f"/tmp/score_seq_input_{suffix}"
    token = f"probe-{uuid.uuid4().hex}"

    os.rename(SEQ_DIR, data_backup)
    os.mkdir(SEQ_DIR)
    os.rename(BIN_PATH, binary_backup)
    try:
        creation_order = ["z_last.dat", "a_first.dat", "m_middle.dat"]
        for index, name in enumerate(creation_order):
            with open(os.path.join(SEQ_DIR, name), "w") as f:
                f.write(f"{index + 1}.0\n")
        with open(os.path.join(SEQ_DIR, "ignored.txt"), "w") as f:
            f.write("999\n")

        wrapper = (
            "#!/bin/bash\n"
            f"cat > {shlex.quote(capture_path)}\n"
            f"printf '%s\\n' {shlex.quote(token)}\n"
        )
        with open(BIN_PATH, "w") as f:
            f.write(wrapper)
        os.chmod(BIN_PATH, 0o755)

        result = subprocess.run(
            [script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
            timeout=15,
            text=True,
        )
        assert result.stdout == token + "\n", (
            "The pipeline did not relay standard output from /home/user/bin/score_seq."
        )
        assert os.path.isfile(capture_path), (
            "The pipeline did not invoke /home/user/bin/score_seq."
        )
        with open(capture_path, "r") as f:
            received = f.read().splitlines()
        expected_paths = sorted(
            os.path.join(SEQ_DIR, name) for name in creation_order
        )
        assert received == expected_paths, (
            "The pipeline did not pipe strictly alphabetically sorted .dat paths "
            "to /home/user/bin/score_seq.\n"
            f"Expected: {expected_paths}\nActual: {received}"
        )
    finally:
        if os.path.lexists(BIN_PATH):
            os.remove(BIN_PATH)
        os.rename(binary_backup, BIN_PATH)
        shutil.rmtree(SEQ_DIR, ignore_errors=True)
        os.rename(data_backup, SEQ_DIR)
        if os.path.exists(capture_path):
            os.remove(capture_path)

    # Also execute the restored real pipeline and compare it with a fresh build.
    with tempfile.TemporaryDirectory() as td:
        reference = os.path.join(td, "reference_score_seq")
        compile_reference(reference)
        expected = expected_for_current_data(reference)
        result = subprocess.run(
            [script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
            timeout=15,
            text=True,
        )
        assert result.stdout.strip() == expected, (
            "The fixed pipeline does not produce the source program's sorted result."
        )


def test_reproducible_output():
    out_path = OUTPUT_PATH
    assert os.path.exists(out_path), f"Output file {out_path} does not exist."
    assert os.path.isfile(out_path), f"Path {out_path} is not a file."

    c_source = SOURCE_PATH
    tmp_bin = "/tmp/test_score_seq"

    try:
        subprocess.run(["gcc", c_source, "-o", tmp_bin], check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to compile the C source code for verification. Error: {e.stderr.decode()}")

    seq_dir = SEQ_DIR
    files = sorted([os.path.join(seq_dir, f) for f in os.listdir(seq_dir) if f.endswith(".dat")])
    input_data = "\n".join(files) + "\n"

    try:
        result = subprocess.run([tmp_bin], input=input_data.encode(), stdout=subprocess.PIPE, check=True)
        expected_output = result.stdout.decode().strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run the verification binary. Error: {e.stderr.decode()}")

    with open(out_path, "r") as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, (
        f"Output in {out_path} does not match expected reproducible output.\n"
        f"Expected: {expected_output}\n"
        f"Actual: {actual_output}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
