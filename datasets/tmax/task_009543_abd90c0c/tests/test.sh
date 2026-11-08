#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest

HOME = Path("/home/user")
CPP = HOME / "report_builder.cpp"
BUILDER = HOME / "report_builder"
SCRIPT = HOME / "process.sh"
ALERT = HOME / "alert.log"
DISK = HOME / "disk_usage.txt"
ROUTES = HOME / "routes.txt"


def test_report_builder_cpp_exists():
    file_path = "/home/user/report_builder.cpp"
    assert os.path.isfile(file_path), f"Missing required file: {file_path}"


def test_report_builder_executable_exists():
    file_path = "/home/user/report_builder"
    assert os.path.isfile(file_path), f"Missing required executable: {file_path}"
    assert os.access(file_path, os.X_OK), f"File {file_path} is not executable"
    with open(file_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {file_path} is not a compiled executable"


def test_process_sh_exists_and_executable():
    file_path = "/home/user/process.sh"
    assert os.path.isfile(file_path), f"Missing required script: {file_path}"
    assert os.access(file_path, os.X_OK), f"Script {file_path} is not executable"
    first_line = Path(file_path).read_text(errors="replace").splitlines()[0]
    assert first_line.startswith("#!") and "bash" in first_line, \
        f"Script {file_path} must be an executable bash script"


def test_alert_log_content():
    file_path = "/home/user/alert.log"
    assert os.path.isfile(file_path), f"Missing required output file: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_content = "GATEWAY: 192.168.1.1\nWARNING_FS: /dev/sda1, /dev/sdb1, /dev/sdd1"

    assert content == expected_content, f"Content of {file_path} does not match expected output.\nExpected:\n{expected_content}\nGot:\n{content}"


def run_builder(executable, input_text, expected):
    ALERT.unlink(missing_ok=True)
    result = subprocess.run(
        [str(executable)],
        input=input_text,
        text=True,
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    assert ALERT.is_file(), "report_builder did not create /home/user/alert.log"
    assert ALERT.read_text().strip() == expected


def test_implementations_and_pipeline_on_varied_inputs():
    original_disk = DISK.read_bytes()
    original_routes = ROUTES.read_bytes()
    original_alert = ALERT.read_bytes() if ALERT.exists() else None
    original_builder_mode = stat.S_IMODE(BUILDER.stat().st_mode)

    with tempfile.TemporaryDirectory(prefix="verify_monitor_") as td_name:
        td = Path(td_name)
        compiled = td / "compiled_from_source"
        real_builder = td / "real_report_builder"
        captured = td / "captured_input"

        try:
            compile_result = subprocess.run(
                ["g++", "-std=c++17", str(CPP), "-o", str(compiled)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            assert compile_result.returncode == 0, \
                f"report_builder.cpp does not compile:\n{compile_result.stderr}"

            multi_input = "198.51.100.44\n/dev/xvda1\nzpool/test\n/dev/nvme0n1p7\n"
            multi_expected = (
                "GATEWAY: 198.51.100.44\n"
                "WARNING_FS: /dev/xvda1, zpool/test, /dev/nvme0n1p7"
            )
            empty_input = "203.0.113.17\n"
            empty_expected = "GATEWAY: 203.0.113.17\nWARNING_FS: NONE"

            # Exercise both the submitted executable and a fresh build of its source.
            run_builder(BUILDER, multi_input, multi_expected)
            run_builder(BUILDER, empty_input, empty_expected)
            run_builder(compiled, multi_input, multi_expected)
            run_builder(compiled, empty_input, empty_expected)

            # Put a recording shim at ./report_builder so process.sh must actually
            # invoke the pipeline target and provide the correctly extracted lines.
            shutil.copy2(BUILDER, real_builder)
            BUILDER.unlink()
            BUILDER.write_text(
                "#!/bin/bash\n"
                "cat > " + repr(str(captured)) + "\n"
                + repr(str(real_builder)) + " < " + repr(str(captured)) + "\n"
            )
            BUILDER.chmod(0o755)

            ROUTES.write_text(
                "172.16.0.0/16 dev eth9 proto kernel\n"
                "default via 203.0.113.9 dev ens4 metric 25\n"
            )
            DISK.write_text(
                "Filesystem 1M-blocks Used Available Use% Mounted on\n"
                "/dev/under 100 79 21 79% /under\n"
                "/dev/vda 100 80 20 80% /\n"
                "pool0 100 100 0 100% /pool\n"
                "/dev/low 100 2 98 2% /low\n"
            )
            ALERT.unlink(missing_ok=True)
            result = subprocess.run(
                [str(SCRIPT)], cwd=str(HOME), text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
            )
            assert result.returncode == 0, result.stderr
            assert captured.is_file(), "process.sh did not invoke ./report_builder"
            assert captured.read_text().splitlines() == [
                "203.0.113.9", "/dev/vda", "pool0"
            ], "process.sh supplied incorrect gateway/filesystem data"
            assert ALERT.read_text().strip() == (
                "GATEWAY: 203.0.113.9\nWARNING_FS: /dev/vda, pool0"
            )

            ROUTES.write_text("default via 10.23.45.67 dev eth0\n")
            DISK.write_text(
                "Filesystem 1M-blocks Used Available Use% Mounted on\n"
                "/dev/a 100 0 100 0% /a\n"
                "/dev/b 100 79 21 79% /b\n"
            )
            captured.unlink(missing_ok=True)
            ALERT.unlink(missing_ok=True)
            result = subprocess.run(
                [str(SCRIPT)], cwd=str(HOME), text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
            )
            assert result.returncode == 0, result.stderr
            assert captured.is_file(), "process.sh did not invoke ./report_builder"
            assert captured.read_text().splitlines() == ["10.23.45.67"]
            assert ALERT.read_text().strip() == (
                "GATEWAY: 10.23.45.67\nWARNING_FS: NONE"
            )
        finally:
            DISK.write_bytes(original_disk)
            ROUTES.write_bytes(original_routes)
            if BUILDER.exists():
                BUILDER.unlink()
            if real_builder.exists():
                shutil.copy2(real_builder, BUILDER)
                BUILDER.chmod(original_builder_mode)
            if original_alert is None:
                ALERT.unlink(missing_ok=True)
            else:
                ALERT.write_bytes(original_alert)
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
