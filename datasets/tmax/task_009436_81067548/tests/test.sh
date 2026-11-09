#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile

WORKSPACE_DIR = "/home/user/matrix_profiler"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_matrix_c_recovered_and_fixed():
    matrix_c = os.path.join(WORKSPACE_DIR, "matrix.c")
    assert os.path.isfile(matrix_c), f"File {matrix_c} was not recovered."

    with open(matrix_c, "r") as f:
        content = f.read()

    # Preserve the original off-by-one assertions.
    assert "i <= 5" not in content, "The off-by-one bug (i <= 5) in matrix.c was not fixed."
    assert "i < 5" in content or "i<=4" in content.replace(" ", ""), "The loop in matrix.c does not seem to be properly fixed."

    # Compile the submitted sources independently with runtime bounds checking and
    # execute the resulting program, rather than trusting the submitted Makefile.
    with tempfile.TemporaryDirectory() as td:
        checked_app = os.path.join(td, "checked_app")
        result = run([
            "gcc", "-O0", "-g", "-fno-omit-frame-pointer",
            "-fsanitize=address,undefined", "main.c", "matrix.c",
            "-o", checked_app
        ], cwd=WORKSPACE_DIR)
        assert result.returncode == 0, f"Submitted sources do not compile:\n{result.stderr}\n{result.stdout}"

        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
        result = run([checked_app], cwd=WORKSPACE_DIR, env=env, timeout=10)
        assert result.returncode == 0, f"Independently compiled program failed:\n{result.stderr}\n{result.stdout}"
        assert "Matrix computation complete" in result.stdout, "Independently compiled program did not complete the matrix computation."


def test_bt_txt_exists_and_valid():
    bt_txt = os.path.join(WORKSPACE_DIR, "bt.txt")
    assert os.path.isfile(bt_txt), f"File {bt_txt} was not created."

    with open(bt_txt, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "compute_matrix" in content or "main" in content, "bt.txt does not contain a valid backtrace (missing 'compute_matrix' or 'main')."

    app_buggy = os.path.join(WORKSPACE_DIR, "app_buggy")
    core = os.path.join(WORKSPACE_DIR, "core")
    assert os.path.isfile(app_buggy), "app_buggy is missing."
    assert os.path.isfile(core) and os.path.getsize(core) > 0, "The supplied core dump is missing or empty."

    actual = run(["gdb", "-batch", "-nx", "-ex", "bt", app_buggy, core], cwd=WORKSPACE_DIR, timeout=20)
    actual_output = actual.stdout + actual.stderr
    assert actual.returncode == 0, f"GDB could not read app_buggy and core:\n{actual_output}"

    actual_frames = re.findall(r"^#\d+.*$", actual_output, flags=re.MULTILINE)
    submitted_frames = re.findall(r"^#\d+.*$", content, flags=re.MULTILINE)
    assert len(submitted_frames) >= 2, "bt.txt does not contain a GDB backtrace with multiple frames."
    assert any("compute_matrix" in frame for frame in submitted_frames), "bt.txt is missing the crashing compute_matrix frame."
    assert any(re.search(r"matrix\.c:\d+", frame) for frame in submitted_frames), "bt.txt does not identify the crashing line in matrix.c."
    assert any("main" in frame for frame in submitted_frames), "bt.txt is missing the main frame."
    assert "buggy_matrix.c" not in content, "The backtrace is not from the recoverable matrix.c bug."

    # Require the recorded frames to agree with a fresh GDB analysis of the supplied core.
    for frame in submitted_frames:
        normalized = re.sub(r"\s+", " ", frame.strip())
        assert any(re.sub(r"\s+", " ", candidate.strip()) == normalized for candidate in actual_frames), \
            f"bt.txt contains a frame not produced by GDB for the supplied core: {frame}"


def test_makefile_fixed_and_compiles():
    makefile = os.path.join(WORKSPACE_DIR, "Makefile")
    assert os.path.isfile(makefile), "Makefile is missing."

    # Preserve the original make check.
    result = run(["make"], cwd=WORKSPACE_DIR)
    assert result.returncode == 0, f"make failed with output:\n{result.stderr}\n{result.stdout}"

    app_fixed = os.path.join(WORKSPACE_DIR, "app_fixed")
    assert os.path.isfile(app_fixed), "make succeeded but app_fixed was not created."
    assert os.access(app_fixed, os.X_OK), "app_fixed is not executable."
    with open(app_fixed, "rb") as f:
        assert f.read(4) == b"\x7fELF", "app_fixed is not a compiled executable."

    result = run(["./app_fixed"], cwd=WORKSPACE_DIR, timeout=10)
    assert result.returncode == 0, f"app_fixed failed:\n{result.stderr}\n{result.stdout}"
    assert "Matrix computation complete" in result.stdout, "app_fixed did not complete the matrix computation."


def test_run_tests_sh():
    run_tests_sh = os.path.join(WORKSPACE_DIR, "run_tests.sh")
    assert os.path.isfile(run_tests_sh), f"File {run_tests_sh} is missing."
    assert os.access(run_tests_sh, os.X_OK), f"File {run_tests_sh} is not executable."

    makefile = os.path.join(WORKSPACE_DIR, "Makefile")
    app_fixed = os.path.join(WORKSPACE_DIR, "app_fixed")
    log_file = os.path.join(WORKSPACE_DIR, "test_results.log")

    with open(makefile, "rb") as f:
        saved_makefile = f.read()
    saved_app = None
    if os.path.exists(app_fixed):
        with open(app_fixed, "rb") as f:
            saved_app = f.read()

    try:
        # Verify the required build-failure assertion and message.
        with open(makefile, "w") as f:
            f.write("all app_fixed:\n\t@exit 1\nclean:\n\t@true\n")
        if os.path.exists(log_file):
            os.remove(log_file)
        result = run(["./run_tests.sh"], cwd=WORKSPACE_DIR, timeout=10)
        assert result.returncode != 0, "run_tests.sh reported success when make failed."
        assert "Build failed" in result.stdout + result.stderr, "run_tests.sh did not print 'Build failed' when make failed."

        # Verify it really runs app_fixed and rejects incorrect output.
        with open(makefile, "w") as f:
            f.write("all app_fixed:\n\t@true\nclean:\n\t@true\n")
        with open(app_fixed, "w") as f:
            f.write("#!/bin/bash\necho 'incorrect output'\nexit 0\n")
        os.chmod(app_fixed, 0o755)
        if os.path.exists(log_file):
            os.remove(log_file)
        result = run(["./run_tests.sh"], cwd=WORKSPACE_DIR, timeout=10)
        assert result.returncode != 0, "run_tests.sh accepted app_fixed output without 'Matrix computation complete'."
    finally:
        with open(makefile, "wb") as f:
            f.write(saved_makefile)
        if saved_app is None:
            if os.path.exists(app_fixed):
                os.remove(app_fixed)
        else:
            with open(app_fixed, "wb") as f:
                f.write(saved_app)
            os.chmod(app_fixed, 0o755)

    # Preserve the original successful-script assertions.
    for name in ("app_fixed", "main.o", "matrix.o"):
        path = os.path.join(WORKSPACE_DIR, name)
        if os.path.exists(path):
            os.remove(path)
    if os.path.exists(log_file):
        os.remove(log_file)

    result = run(["./run_tests.sh"], cwd=WORKSPACE_DIR, timeout=20)
    assert result.returncode == 0, f"run_tests.sh failed with output:\n{result.stderr}\n{result.stdout}"
    assert os.path.isfile(log_file), f"{log_file} was not created by run_tests.sh."

    with open(log_file, "r") as f:
        content = f.read()
    assert "ALL TESTS PASSED" in content, f"{log_file} does not contain 'ALL TESTS PASSED'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
