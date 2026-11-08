#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import builtins
import contextlib
import io
import os
import runpy
import secrets
import shutil
import subprocess
import sys
import uuid

TOTAL = "/home/user/total_errors.txt"
PROCESS = "/home/user/process.py"
PIPELINE = "/home/user/process_logs.sh"
LOGS = "/home/user/logs"
MRE = "/home/user/mre.py"
MRE_LOG = "/home/user/mre_test.log"


def test_total_errors_count():
    filepath = TOTAL
    assert os.path.isfile(filepath), f"{filepath} does not exist. Did you run the script?"

    with open(filepath, "r") as f:
        content = f.read().strip()

    assert content == "3", f"Expected total errors to be 3, but got {content}. Check if process_logs.sh processes all files and process.py handles corrupted files correctly."


def test_processing_scripts_exist():
    assert os.path.isfile(PROCESS), f"{PROCESS} does not exist."
    assert os.path.isfile(PIPELINE), f"{PIPELINE} does not exist."
    assert os.access(PIPELINE, os.X_OK), f"{PIPELINE} is not executable."


def test_process_py_handles_dynamic_corrupt_log():
    original_total = None
    total_existed = os.path.exists(TOTAL)
    if total_existed:
        with open(TOTAL, "rb") as f:
            original_total = f.read()

    test_log = f"/home/user/process verifier {uuid.uuid4().hex}.log"
    rng = secrets.SystemRandom()
    count = rng.randint(2, 8)
    initial = rng.randint(10, 100)

    try:
        payload = b"INFO: start\n" + b"".join(
            b"ERROR: generated entry \xff\n" if i == 0 else b"ERROR: generated entry\n"
            for i in range(count)
        )
        with open(test_log, "wb") as f:
            f.write(payload)
        with open(TOTAL, "w") as f:
            f.write(f"{initial}\n")

        result = subprocess.run(
            ["python3", PROCESS, test_log], capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, (
            f"process.py failed on a corrupt log.\nStdout: {result.stdout}\nStderr: {result.stderr}"
        )
        with open(TOTAL, "r") as f:
            actual = f.read().strip()
        assert actual == str(initial + count), (
            f"process.py produced total {actual}; expected {initial + count}."
        )
    finally:
        if os.path.exists(test_log):
            os.remove(test_log)
        if total_existed:
            with open(TOTAL, "wb") as f:
                f.write(original_total)
        elif os.path.exists(TOTAL):
            os.remove(TOTAL)


def test_pipeline_executes_on_dynamic_logs_with_spaces_and_corruption():
    backup = f"/home/user/logs.verifier-backup-{uuid.uuid4().hex}"
    assert os.path.isdir(LOGS), f"{LOGS} does not exist."
    os.rename(LOGS, backup)
    os.mkdir(LOGS)

    rng = secrets.SystemRandom()
    counts = [rng.randint(1, 5), rng.randint(2, 7), rng.randint(1, 4)]
    expected = sum(counts)
    names = [
        f"generated log with spaces {uuid.uuid4().hex}.txt",
        f"corrupt-{uuid.uuid4().hex}.log",
        f"ordinary-{uuid.uuid4().hex}.txt",
    ]

    try:
        for index, (name, count) in enumerate(zip(names, counts)):
            data = b"INFO: generated fixture\n"
            for line_number in range(count):
                if index == 1 and line_number == 0:
                    data += b"ERROR: corrupt byte \xff present\n"
                else:
                    data += b"ERROR: generated failure\n"
            with open(os.path.join(LOGS, name), "wb") as f:
                f.write(data)

        result = subprocess.run(
            [PIPELINE], capture_output=True, text=True, timeout=20
        )
        assert result.returncode == 0, (
            f"process_logs.sh failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"
        )
        assert os.path.isfile(TOTAL), "process_logs.sh did not create total_errors.txt."
        with open(TOTAL, "r") as f:
            actual = f.read().strip()
        assert actual == str(expected), (
            f"Dynamic pipeline run expected {expected} errors but got {actual}."
        )
    finally:
        shutil.rmtree(LOGS, ignore_errors=True)
        os.rename(backup, LOGS)
        with open(TOTAL, "w") as f:
            f.write("3\n")


def test_mre_script_exists():
    filepath = MRE
    assert os.path.isfile(filepath), f"MRE script {filepath} does not exist."


def test_mre_script_execution():
    filepath = MRE
    assert os.path.isfile(filepath), f"MRE script {filepath} does not exist."

    result = subprocess.run(["python3", filepath], capture_output=True, text=True, timeout=15)

    assert result.returncode == 0, f"MRE script exited with non-zero code {result.returncode}.\nStderr: {result.stderr}"
    assert "Traceback interpreted correctly" in result.stdout, "MRE script did not output 'Traceback interpreted correctly' as expected."


def _handler_mentions_unicode_decode_error(handler_type):
    if isinstance(handler_type, ast.Name):
        return handler_type.id == "UnicodeDecodeError"
    if isinstance(handler_type, ast.Attribute):
        return handler_type.attr == "UnicodeDecodeError"
    if isinstance(handler_type, ast.Tuple):
        return any(_handler_mentions_unicode_decode_error(item) for item in handler_type.elts)
    return False


def test_mre_really_creates_corrupt_file_and_catches_decode_error():
    with open(MRE, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=MRE)
    assert any(
        isinstance(node, ast.ExceptHandler)
        and _handler_mentions_unicode_decode_error(node.type)
        for node in ast.walk(tree)
    ), "mre.py must explicitly catch UnicodeDecodeError."

    if os.path.exists(MRE_LOG):
        os.remove(MRE_LOG)

    original_open = builtins.open
    state = {"default_text_open": False, "decode_error_raised": False}

    class TrackingReader:
        def __init__(self, wrapped):
            self.wrapped = wrapped

        def _call(self, method, *args, **kwargs):
            try:
                return getattr(self.wrapped, method)(*args, **kwargs)
            except UnicodeDecodeError:
                state["decode_error_raised"] = True
                raise

        def read(self, *args, **kwargs):
            return self._call("read", *args, **kwargs)

        def readline(self, *args, **kwargs):
            return self._call("readline", *args, **kwargs)

        def readlines(self, *args, **kwargs):
            return self._call("readlines", *args, **kwargs)

        def __iter__(self):
            return self

        def __next__(self):
            return self._call("__next__")

        def __enter__(self):
            self.wrapped.__enter__()
            return self

        def __exit__(self, *args):
            return self.wrapped.__exit__(*args)

        def __getattr__(self, name):
            return getattr(self.wrapped, name)

    def tracking_open(file, *args, **kwargs):
        wrapped = original_open(file, *args, **kwargs)
        try:
            path = os.path.abspath(os.fspath(file))
        except TypeError:
            return wrapped

        mode = args[0] if args else kwargs.get("mode", "r")
        errors = args[3] if len(args) > 3 else kwargs.get("errors")
        if path == MRE_LOG and mode == "r" and errors is None:
            state["default_text_open"] = True
            return TrackingReader(wrapped)
        return wrapped

    output = io.StringIO()
    old_argv = sys.argv
    try:
        builtins.open = tracking_open
        sys.argv = [MRE]
        with contextlib.redirect_stdout(output):
            runpy.run_path(MRE, run_name="__main__")
    finally:
        builtins.open = original_open
        sys.argv = old_argv

    assert output.getvalue() == "Traceback interpreted correctly\n", (
        "mre.py must print exactly 'Traceback interpreted correctly' when the exception is caught."
    )
    assert os.path.isfile(MRE_LOG), "mre.py did not create /home/user/mre_test.log."
    with original_open(MRE_LOG, "rb") as f:
        raw = f.read()
    try:
        raw.decode("utf-8")
    except UnicodeDecodeError:
        pass
    else:
        raise AssertionError("mre_test.log does not contain invalid UTF-8 data.")

    assert state["default_text_open"], "mre.py did not open mre_test.log in default text mode."
    assert state["decode_error_raised"], "Reading mre_test.log did not raise UnicodeDecodeError."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
