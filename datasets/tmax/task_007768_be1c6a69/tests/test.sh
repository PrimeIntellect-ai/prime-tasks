#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile


def run(command, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 120)
    return subprocess.run(command, **kwargs)


def test_deploy_script_exists_and_executable():
    path = "/home/user/deploy.sh"
    assert os.path.isfile(path), f"File {path} does not exist"
    assert os.access(path, os.X_OK), f"File {path} is not executable"


def test_required_sources_exist_before_deployment():
    expect_path = "/home/user/fetch_metrics.exp"
    source_path = "/home/user/analyzer/src/main.rs"

    assert os.path.isfile(expect_path), f"File {expect_path} does not exist"
    result = run(["expect", expect_path])
    assert result.returncode == 0, (
        f"fetch_metrics.exp is not a working expect script\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    normalized = result.stdout.replace("\r", "")
    for row in ("host1,45,1024", "host2,60,2048", "host3,80,4096"):
        assert row in normalized.splitlines(), f"Expected CSV row {row!r} on stdout, got {result.stdout!r}"
    assert "Auth failed" not in normalized

    assert os.path.isfile(source_path), f"File {source_path} does not exist"
    with open(source_path, "r", encoding="utf-8") as source_file:
        source = source_file.read()
    assert "REPORT_PATH" in source, "main.rs does not read the REPORT_PATH environment variable"
    assert "/tmp/wrong_path.txt" not in source, "main.rs still contains the old hardcoded output path"


def test_deploy_script_succeeds():
    path = "/home/user/deploy.sh"
    assert os.path.isfile(path), "deploy.sh is missing, cannot run it."
    result = subprocess.run([path], capture_output=True, text=True)
    assert result.returncode == 0, f"deploy.sh failed with return code {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"


def test_symlink_points_to_analyzer_v2():
    path = "/home/user/bin/analyzer"
    assert os.path.islink(path), f"Symlink {path} does not exist"
    target = os.readlink(path)
    abs_target = os.path.abspath(os.path.join(os.path.dirname(path), target))
    assert abs_target == "/home/user/bin/analyzer_v2", f"Symlink {path} points to {target}, expected /home/user/bin/analyzer_v2"


def test_final_report_exists_and_correct():
    path = "/home/user/final_report.txt"
    assert os.path.isfile(path), f"File {path} does not exist. The analyzer might not have written to REPORT_PATH correctly."
    with open(path, "r") as f:
        content = f.read()
    assert content == "Total Mem: 7168\n", f"Expected 'Total Mem: 7168\\n', but got {repr(content)}"


def test_deployed_analyzer_honors_report_path_and_default():
    binary = "/home/user/bin/analyzer_v2"
    cargo_binary = "/home/user/analyzer/target/release/analyzer"
    assert os.path.isfile(binary), "The staged analyzer_v2 binary was not created"
    assert os.access(binary, os.X_OK), "The staged analyzer_v2 is not executable"
    with open(binary, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "analyzer_v2 is not a compiled executable"
    assert os.path.isfile(cargo_binary), "cargo release output is missing"
    assert shutil.cmp(binary, cargo_binary, shallow=False), "analyzer_v2 is not a copy of the cargo release binary"

    values = [secrets.randbelow(50000) + 1 for _ in range(5)]
    csv_input = "".join(f"dynamic-{i},{i + 3},{value}\n" for i, value in enumerate(values))
    expected = f"Total Mem: {sum(values)}\n"

    with tempfile.TemporaryDirectory() as temp_dir:
        requested_report = os.path.join(temp_dir, "chosen-report.txt")
        env = os.environ.copy()
        env["REPORT_PATH"] = requested_report
        result = run([binary], input=csv_input, cwd=temp_dir, env=env)
        assert result.returncode == 0, f"Analyzer failed with REPORT_PATH: {result.stderr}"
        assert os.path.isfile(requested_report), "Analyzer ignored REPORT_PATH"
        with open(requested_report, "r", encoding="utf-8") as report:
            assert report.read() == expected
        assert not os.path.exists(os.path.join(temp_dir, "report.txt")), "Analyzer used the default despite REPORT_PATH"

        os.unlink(requested_report)
        env.pop("REPORT_PATH", None)
        result = run([binary], input=csv_input, cwd=temp_dir, env=env)
        assert result.returncode == 0, f"Analyzer failed without REPORT_PATH: {result.stderr}"
        default_report = os.path.join(temp_dir, "report.txt")
        assert os.path.isfile(default_report), "Analyzer did not default to report.txt"
        with open(default_report, "r", encoding="utf-8") as report:
            assert report.read() == expected


def test_expect_authentication_and_dynamic_end_to_end_redeployment():
    cli_path = "/home/user/cap_cli.sh"
    expect_path = "/home/user/fetch_metrics.exp"
    deploy_path = "/home/user/deploy.sh"
    binary = "/home/user/bin/analyzer_v2"
    cargo_binary = "/home/user/analyzer/target/release/analyzer"
    report_path = "/home/user/final_report.txt"

    with open(cli_path, "rb") as cli_file:
        original_cli = cli_file.read()
    original_mode = stat.S_IMODE(os.stat(cli_path).st_mode)

    values = [secrets.randbelow(9000) + 101 for _ in range(4)]
    rows = [f"challenge-{secrets.token_hex(4)}-{i},{10 + i},{value}" for i, value in enumerate(values)]
    replacement = "#!/bin/bash\n" \
        "read -r -s -p \"Enter capacity planner password: \" pass\n" \
        "echo\n" \
        "if [ \"$pass\" != \"cap123\" ]; then echo 'Auth failed'; exit 37; fi\n" \
        + "\n".join(f"echo '{row}'" for row in rows) + "\n"

    try:
        with open(cli_path, "w", encoding="utf-8") as cli_file:
            cli_file.write(replacement)
        os.chmod(cli_path, 0o755)

        fetched = run(["expect", expect_path])
        assert fetched.returncode == 0, (
            f"Expect authentication failed\nStdout: {fetched.stdout}\nStderr: {fetched.stderr}"
        )
        output_lines = fetched.stdout.replace("\r", "").splitlines()
        for row in rows:
            assert row in output_lines, f"fetch_metrics.exp did not emit dynamic CSV row {row!r}"
        assert "Auth failed" not in fetched.stdout

        for path in (binary, cargo_binary, report_path):
            if os.path.lexists(path):
                os.unlink(path)
        link = "/home/user/bin/analyzer"
        if os.path.lexists(link):
            os.unlink(link)
        os.symlink("/home/user/bin/analyzer_v1", link)

        deployed = run([deploy_path], timeout=180)
        assert deployed.returncode == 0, (
            f"Fresh dynamic deployment failed\nStdout: {deployed.stdout}\nStderr: {deployed.stderr}"
        )
        assert os.path.isfile(cargo_binary), "Deployment did not recreate target/release/analyzer"
        assert os.path.isfile(binary), "Deployment did not stage analyzer_v2"
        with open(binary, "rb") as executable:
            assert executable.read(4) == b"\x7fELF", "Staged analyzer is not a compiled executable"
        assert shutil.cmp(binary, cargo_binary, shallow=False), "Staged binary differs from cargo release output"
        assert os.path.islink(link), "Deployment did not create the analyzer symlink"
        target = os.path.abspath(os.path.join(os.path.dirname(link), os.readlink(link)))
        assert target == binary, f"Deployment symlink points to {target}, expected {binary}"
        with open(report_path, "r", encoding="utf-8") as report:
            assert report.read() == f"Total Mem: {sum(values)}\n"
    finally:
        with open(cli_path, "wb") as cli_file:
            cli_file.write(original_cli)
        os.chmod(cli_path, original_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
