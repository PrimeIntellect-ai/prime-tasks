#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import subprocess
from datetime import datetime
from zoneinfo import ZoneInfo


def test_capacity_report_exists_and_correct():
    report_path = "/home/user/capacity_report.eml"
    assert os.path.exists(report_path), f"Expected report file {report_path} does not exist."

    expected_content = (
        "To: admin@example.com\n"
        "From: planner@example.com\n"
        "Subject: Capacity Report\n"
        "Date: Wed, 23 Oct 2024 15:00:00 +0900\n"
        "\n"
        "Environment: dev\n"
        "Total Memory: 256 MB\n"
        "Total CPU: 10.0%\n"
        "\n"
        "Environment: prod\n"
        "Total Memory: 1600 MB\n"
        "Total CPU: 115.5%\n"
    )

    with open(report_path, "r") as f:
        actual_content = f.read()

    actual_content = actual_content.replace("\r\n", "\n").strip()
    expected_content = expected_content.strip()

    assert actual_content == expected_content, (
        f"Content of {report_path} does not match the expected format or values.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )


def test_kill_script_exists_and_correct():
    script_path = "/home/user/kill_high_cpu.sh"
    assert os.path.exists(script_path), f"Expected script file {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

    expected_lines = [
        "#!/bin/bash",
        "kill -9 1001",
    ]

    with open(script_path, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines[0] == expected_lines[0], (
        f"First line of {script_path} must be {expected_lines[0]}"
    )
    assert "kill -9 1001" in actual_lines, f"Expected 'kill -9 1001' in {script_path}"

    kills = [line for line in actual_lines if line.startswith("kill ")]
    assert len(kills) == 1, (
        f"Expected exactly 1 kill command in {script_path}, found {len(kills)}"
    )


def test_analyzer_is_valid_and_processes_fresh_inputs():
    analyzer = "/home/user/analyzer.go"
    assert os.path.exists(analyzer), f"Expected Go source {analyzer} does not exist."
    assert stat.S_ISREG(os.lstat(analyzer).st_mode), f"{analyzer} must be a regular file."

    token = secrets.token_hex(5)
    env_a = f"a_{token}"
    env_z = f"z_{token}"
    app1 = f"app_one_{token}"
    app2 = f"app_two_{token}"
    app3 = f"app_three_{token}"
    app4 = f"app_four_{token}"

    pid_base = 20000 + secrets.randbelow(20000)
    mem_base = 300 + secrets.randbelow(500)
    metrics = [
        {"pid": pid_base + 1, "app": app1, "memory_mb": mem_base + 11, "cpu_percent": 51.5},
        {"pid": pid_base + 2, "app": app2, "memory_mb": mem_base + 22, "cpu_percent": 8.0},
        {"pid": pid_base + 3, "app": app3, "memory_mb": mem_base + 33, "cpu_percent": 77.0},
        {"pid": pid_base + 4, "app": app4, "memory_mb": mem_base + 44, "cpu_percent": 50.0},
    ]
    app_env = {
        app1: env_z,
        app2: env_z,
        app3: env_a,
        app4: env_a,
    }

    apps_dir = "/home/user/apps"
    metrics_dir = "/home/user/mock_metrics"
    deployments_dir = "/home/user/deployments"
    shutil.rmtree(apps_dir)
    shutil.rmtree(metrics_dir)
    os.makedirs(apps_dir)
    os.makedirs(metrics_dir)
    os.makedirs(os.path.join(deployments_dir, env_a), exist_ok=True)
    os.makedirs(os.path.join(deployments_dir, env_z), exist_ok=True)

    for index, (app, env) in enumerate(app_env.items()):
        app_dir = os.path.join(apps_dir, app)
        os.makedirs(app_dir)
        if index % 2 == 0:
            target = os.path.join(deployments_dir, env)
        else:
            target = os.path.join("..", "..", "deployments", env)
        os.symlink(target, os.path.join(app_dir, "env"))

    for item in metrics:
        with open(os.path.join(metrics_dir, f"{item['pid']}.json"), "w") as f:
            json.dump(item, f)

    timestamp = 1600000000 + secrets.randbelow(300000000)
    report_path = "/home/user/capacity_report.eml"
    script_path = "/home/user/kill_high_cpu.sh"
    for path in (report_path, script_path):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ["go", "run", analyzer, str(timestamp)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=45,
    )
    assert result.returncode == 0, (
        "analyzer.go did not compile and run successfully with the timestamp argument.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    totals = {}
    for item in metrics:
        env = app_env[item["app"]]
        totals.setdefault(env, [0, 0.0])
        totals[env][0] += item["memory_mb"]
        totals[env][1] += item["cpu_percent"]

    formatted_date = datetime.fromtimestamp(timestamp, ZoneInfo("Asia/Tokyo")).strftime(
        "%a, %d %b %Y %H:%M:%S %z"
    )
    body_blocks = []
    for env in sorted(totals):
        memory, cpu = totals[env]
        body_blocks.append(
            f"Environment: {env}\n"
            f"Total Memory: {memory} MB\n"
            f"Total CPU: {cpu:.1f}%"
        )
    expected_report = (
        "To: admin@example.com\n"
        "From: planner@example.com\n"
        "Subject: Capacity Report\n"
        f"Date: {formatted_date}\n\n"
        + "\n\n".join(body_blocks)
    )

    assert os.path.exists(report_path), "Running analyzer.go did not create the email report."
    with open(report_path, "r") as f:
        actual_report = f.read().replace("\r\n", "\n").strip()
    assert actual_report == expected_report.strip(), (
        f"Analyzer report for fresh metrics was incorrect.\n"
        f"Expected:\n{expected_report}\n\nActual:\n{actual_report}"
    )

    assert os.path.exists(script_path), "Running analyzer.go did not create the kill script."
    mode = os.stat(script_path).st_mode
    assert bool(mode & stat.S_IXUSR), "Generated kill script is not executable."
    with open(script_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines and lines[0] == "#!/bin/bash", "Generated kill script has the wrong shebang."
    actual_kills = [line for line in lines if line.startswith("kill ")]
    expected_kills = sorted(
        f"kill -9 {item['pid']}" for item in metrics if item["cpu_percent"] > 50.0
    )
    assert sorted(actual_kills) == expected_kills, (
        f"Generated kill commands were incorrect: expected {expected_kills}, got {actual_kills}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
