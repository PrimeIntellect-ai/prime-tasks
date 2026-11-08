#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import string
import subprocess
import tempfile


def expected_cost(value):
    return str(sum(ord(ch) for ch in value))


def run_and_check(tool, value):
    proc = subprocess.run(
        [tool],
        input=value,
        text=True,
        capture_output=True,
        check=True,
        timeout=5,
    )
    assert proc.stdout.strip() == expected_cost(value), (
        f"Incorrect output for input of length {len(value)}: "
        f"expected {expected_cost(value)}, got {proc.stdout.strip()}"
    )


def test_symlink_created():
    symlink_path = "/home/user/vm-logs"
    target_path = "/tmp/qemu-vms"

    assert os.path.islink(symlink_path), f"Expected {symlink_path} to be a symbolic link."
    actual_target = os.readlink(symlink_path)
    assert actual_target.rstrip('/') == target_path.rstrip('/'), (
        f"Symlink {symlink_path} points to {actual_target}, expected {target_path}"
    )


def test_pipeline_script_fixes():
    script_path = "/home/user/pipeline/run_cost.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    with open(script_path, "r") as f:
        content = f.read()

    assert "/home/user/bin/netcost" in content, (
        "Pipeline script does not use the absolute path for the tool (/home/user/bin/netcost)."
    )
    assert "/home/user/reports/cost.out" in content, (
        "Pipeline script does not use the absolute path for the output file (/home/user/reports/cost.out)."
    )


def test_pipeline_script_execution():
    script_path = "/home/user/pipeline/run_cost.sh"
    output_path = "/home/user/reports/cost.out"
    log_path = "/tmp/qemu-vms/log1.txt"
    tool_path = "/home/user/bin/netcost"
    saved_tool = "/home/user/bin/.netcost-verifier-real"
    marker = "/tmp/netcost-pipeline-invoked"

    payload = "pipeline_" + secrets.token_hex(24)
    with open(log_path, "w") as f:
        f.write(payload + "\n")

    for path in (output_path, marker, saved_tool):
        if os.path.lexists(path):
            os.remove(path)

    os.replace(tool_path, saved_tool)
    try:
        with open(tool_path, "w") as f:
            f.write("#!/bin/bash\n")
            f.write(f"/usr/bin/touch {marker}\n")
            f.write(f"exec {saved_tool}\n")
        os.chmod(tool_path, 0o755)

        env = os.environ.copy()
        env["PATH"] = ""
        result = subprocess.run(
            ["/bin/bash", script_path],
            cwd="/tmp",
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"Pipeline script failed with empty PATH from another directory: {result.stderr}"
        )
        assert os.path.isfile(marker), "Pipeline script did not invoke /home/user/bin/netcost."
        assert os.path.isfile(output_path), f"Output file {output_path} was not created."

        with open(output_path, "r") as f:
            output_content = f.read().strip()
        assert output_content == expected_cost(payload), (
            f"Pipeline output was {output_content!r}, expected {expected_cost(payload)!r}."
        )
    finally:
        if os.path.lexists(tool_path):
            os.remove(tool_path)
        if os.path.lexists(saved_tool):
            os.replace(saved_tool, tool_path)
        if os.path.lexists(marker):
            os.remove(marker)


def test_corrected_source_builds_and_works():
    source = "/app/netcost-1.2.0/processor.cpp"
    assert os.path.isfile(source), f"Corrected source {source} is missing."

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "netcost")
        build = subprocess.run(
            ["/usr/bin/g++", "-O2", source, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"Corrected source does not compile: {build.stderr}"
        for value in ("", "A", "AB", "last_byte_check"):
            run_and_check(rebuilt, value)


def test_fuzz_equivalence():
    agent_tool = "/home/user/bin/netcost"
    assert os.path.isfile(agent_tool), f"Agent tool {agent_tool} is missing."
    assert os.access(agent_tool, os.X_OK), f"Agent tool {agent_tool} is not executable."

    with open(agent_tool, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Agent tool {agent_tool} is not a compiled ELF executable."

    for value in ("", "A", "0", "AB", "a9Z"):
        run_and_check(agent_tool, value)

    random.seed(42)
    charset = string.ascii_letters + string.digits
    for i in range(200):
        length = random.randint(10, 1000)
        input_str = "".join(random.choices(charset, k=length))
        proc = subprocess.run(
            [agent_tool],
            input=input_str,
            text=True,
            capture_output=True,
            check=True,
            timeout=5,
        )
        agent_out = proc.stdout.strip()
        expected = expected_cost(input_str)
        assert agent_out == expected, (
            f"Mismatch on fuzz iteration {i}.\n"
            f"Input length: {length}\n"
            f"Expected output: {expected}\n"
            f"Agent output: {agent_out}\n"
            f"Input string: {input_str}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
