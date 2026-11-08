#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import tempfile
import uuid


def test_c_source_exists():
    c_file = "/home/user/src/quota_calc.c"
    assert os.path.isfile(c_file), f"C source file {c_file} is missing."


def test_c_executable_exists_and_is_elf():
    exe_file = "/home/user/bin/quota_calc"
    assert os.path.isfile(exe_file), f"Executable {exe_file} is missing."

    st = os.stat(exe_file)
    assert st.st_mode & stat.S_IXUSR, f"File {exe_file} is not executable."

    with open(exe_file, "rb") as f:
        magic = f.read(4)
        assert magic == b"\x7fELF", f"File {exe_file} is not a valid ELF executable."


def test_bash_script_exists_and_executable():
    script_file = "/home/user/bin/run_checks.sh"
    assert os.path.isfile(script_file), f"Bash script {script_file} is missing."

    st = os.stat(script_file)
    assert st.st_mode & stat.S_IXUSR, f"Bash script {script_file} is not executable."


def test_report_exists_and_contents():
    report_file = "/home/user/logs/quota_report.txt"
    assert os.path.isfile(report_file), f"Report file {report_file} is missing."

    expected_lines = [
        "/home/user/users/alice TOTAL_BYTES: 6000 STATUS: OK",
        "/home/user/users/bob TOTAL_BYTES: 15000 STATUS: EXCEEDED",
        "/home/user/users/charlie TOTAL_BYTES: 12000 STATUS: EXCEEDED"
    ]

    with open(report_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Report file contents do not match expected.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def run_calc(executable, directory):
    result = subprocess.run(
        [executable, directory], text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{executable} failed for {directory}: {result.stderr}"
    )
    return result.stdout


def exercise_calculator(executable):
    with tempfile.TemporaryDirectory(prefix="quota_dynamic_") as workspace:
        boundary = os.path.join(workspace, "boundary")
        nested = os.path.join(boundary, "one", "two")
        os.makedirs(nested)
        with open(os.path.join(boundary, "root.bin"), "wb") as f:
            f.write(os.urandom(4001))
        with open(os.path.join(nested, "nested.bin"), "wb") as f:
            f.write(os.urandom(6239))

        external = os.path.join(workspace, "external.bin")
        with open(external, "wb") as f:
            f.write(os.urandom(7777))
        os.symlink(external, os.path.join(boundary, "ignored-file-link"))

        external_dir = os.path.join(workspace, "external-dir")
        os.mkdir(external_dir)
        with open(os.path.join(external_dir, "ignored.bin"), "wb") as f:
            f.write(os.urandom(8888))
        os.symlink(external_dir, os.path.join(boundary, "ignored-dir-link"))

        expected = f"{boundary} TOTAL_BYTES: 10240 STATUS: OK\n"
        assert run_calc(executable, boundary) == expected

        exceeded = os.path.join(workspace, "exceeded")
        os.makedirs(os.path.join(exceeded, "deep"))
        with open(os.path.join(exceeded, "a.bin"), "wb") as f:
            f.write(os.urandom(5000))
        with open(os.path.join(exceeded, "deep", "b.bin"), "wb") as f:
            f.write(os.urandom(5241))

        expected = f"{exceeded} TOTAL_BYTES: 10241 STATUS: EXCEEDED\n"
        assert run_calc(executable, exceeded) == expected

    no_args = subprocess.run([executable], capture_output=True, timeout=10)
    assert no_args.returncode != 0, "quota_calc must reject a missing argument"
    extra_args = subprocess.run(
        [executable, "/tmp", "/tmp"], capture_output=True, timeout=10
    )
    assert extra_args.returncode != 0, "quota_calc must reject extra arguments"


def immediate_user_directories():
    root = "/home/user/users"
    return sorted(
        entry.path
        for entry in os.scandir(root)
        if entry.is_dir(follow_symlinks=False)
    )


def regular_file_total(root):
    total = 0
    for current, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [
            name for name in dirs
            if not os.path.islink(os.path.join(current, name))
        ]
        for name in files:
            path = os.path.join(current, name)
            mode = os.lstat(path).st_mode
            if stat.S_ISREG(mode):
                total += os.lstat(path).st_size
    return total


def read_nonempty_report_lines():
    with open("/home/user/logs/quota_report.txt", "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_source_binary_and_automation_behavior():
    source = "/home/user/src/quota_calc.c"
    submitted_exe = "/home/user/bin/quota_calc"
    script = "/home/user/bin/run_checks.sh"

    compiled = os.path.join(tempfile.gettempdir(), "quota_from_source_" + uuid.uuid4().hex)
    compile_result = subprocess.run(
        ["gcc", source, "-o", compiled], text=True, capture_output=True, timeout=20
    )
    assert compile_result.returncode == 0, (
        "quota_calc.c does not compile:\n" + compile_result.stderr
    )

    try:
        exercise_calculator(compiled)
        exercise_calculator(submitted_exe)
    finally:
        if os.path.exists(compiled):
            os.unlink(compiled)

    dynamic_name = "verify_" + uuid.uuid4().hex
    dynamic_dir = os.path.join("/home/user/users", dynamic_name)
    os.makedirs(os.path.join(dynamic_dir, "nested"))
    with open(os.path.join(dynamic_dir, "first.bin"), "wb") as f:
        f.write(os.urandom(3217))
    with open(os.path.join(dynamic_dir, "nested", "second.bin"), "wb") as f:
        f.write(os.urandom(8129))

    # Replace quota_calc briefly with an instrumented stand-in to prove that
    # run_checks.sh invokes the required path once for every user directory and
    # captures and sorts those invocations' output.
    token = uuid.uuid4().hex
    call_log = "/tmp/quota_calls_" + token
    backup = "/tmp/quota_binary_" + token
    sentinel_size = 1000 + (int(token[:6], 16) % 8000)
    shutil.copy2(submitted_exe, backup)
    try:
        with open(submitted_exe, "w") as f:
            f.write("#!/bin/bash\n")
            f.write(f"printf '%s\\t%s\\n' \"$#\" \"$1\" >> '{call_log}'\n")
            f.write(
                f"printf '%s TOTAL_BYTES: {sentinel_size} STATUS: OK\\n' \"$1\"\n"
            )
        os.chmod(submitted_exe, 0o755)

        result = subprocess.run([script], text=True, capture_output=True, timeout=20)
        assert result.returncode == 0, "run_checks.sh failed: " + result.stderr

        directories = immediate_user_directories()
        with open(call_log, "r") as f:
            calls = [line.rstrip("\n").split("\t", 1) for line in f]
        assert sorted(calls) == sorted([["1", path] for path in directories]), (
            "run_checks.sh must invoke /home/user/bin/quota_calc exactly once "
            "with each top-level user directory"
        )

        expected_wrapper_report = sorted(
            f"{path} TOTAL_BYTES: {sentinel_size} STATUS: OK"
            for path in directories
        )
        assert read_nonempty_report_lines() == expected_wrapper_report, (
            "run_checks.sh did not capture and sort quota_calc output correctly"
        )
    finally:
        shutil.copy2(backup, submitted_exe)
        os.unlink(backup)
        if os.path.exists(call_log):
            os.unlink(call_log)

    # Execute the real submitted binary through the submitted script on the
    # randomized tree and derive the expected report from the filesystem.
    result = subprocess.run([script], text=True, capture_output=True, timeout=20)
    assert result.returncode == 0, "run_checks.sh failed with quota_calc: " + result.stderr

    expected = []
    for directory in immediate_user_directories():
        size = regular_file_total(directory)
        status_text = "EXCEEDED" if size > 10240 else "OK"
        expected.append(
            f"{directory} TOTAL_BYTES: {size} STATUS: {status_text}"
        )
    expected.sort()
    assert read_nonempty_report_lines() == expected, (
        "The dynamically generated quota report is incorrect"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
