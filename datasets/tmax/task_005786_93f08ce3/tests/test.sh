#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shlex
import subprocess
import sys
import tempfile

import pytest


def test_configure_script_runs_wizard_and_creates_conf():
    configure_path = '/home/user/configure.py'
    wizard_path = '/home/user/setup_wizard.sh'
    conf_path = '/home/user/operator.conf'

    assert os.path.isfile(configure_path), f"{configure_path} is missing."
    assert os.path.isfile(wizard_path), f"{wizard_path} is missing."

    with open(wizard_path, 'rb') as f:
        original_wizard = f.read()
    original_mode = os.stat(wizard_path).st_mode

    fd, saved_wizard = tempfile.mkstemp(prefix='setup_wizard_', suffix='.sh')
    os.close(fd)
    marker = saved_wizard + '.invoked'

    try:
        with open(saved_wizard, 'wb') as f:
            f.write(original_wizard)
        os.chmod(saved_wizard, original_mode)

        wrapper = f'''#!/bin/bash
printf 'invoked\\n' > {shlex.quote(marker)}
exec {shlex.quote(saved_wizard)} "$@"
'''
        with open(wizard_path, 'w') as f:
            f.write(wrapper)
        os.chmod(wizard_path, 0o755)

        if os.path.lexists(marker):
            os.unlink(marker)
        if os.path.lexists(conf_path):
            os.unlink(conf_path)

        result = subprocess.run(
            [sys.executable, configure_path],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=20,
        )

        assert result.returncode == 0, (
            f"Running {configure_path} failed with exit code {result.returncode}:\n"
            f"{result.stdout}"
        )
        assert os.path.isfile(marker), (
            f"{configure_path} did not invoke {wizard_path}."
        )
        assert os.path.isfile(conf_path), (
            f"{conf_path} is missing after running {configure_path}."
        )

        with open(conf_path, 'r') as f:
            content = f.read()

        assert "env=production" in content, f"{conf_path} missing 'env=production'."
        assert "dir=/home/user/manifests/active" in content, (
            f"{conf_path} missing 'dir=/home/user/manifests/active'."
        )
    finally:
        with open(wizard_path, 'wb') as f:
            f.write(original_wizard)
        os.chmod(wizard_path, original_mode)
        for path in (saved_wizard, marker):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def _points_to(link_path, expected_path):
    target = os.readlink(link_path)
    return (
        target == expected_path
        or os.path.abspath(os.path.join(os.path.dirname(link_path), target)) == expected_path
    )


def test_manifest_symlinks_derived_from_available_yaml():
    active_dir = '/home/user/manifests/active'
    available_dir = '/home/user/manifests/available'

    assert os.path.isdir(active_dir), f"{active_dir} directory is missing."
    assert os.path.isdir(available_dir), f"{available_dir} directory is missing."

    expected_deployments = set()
    yaml_names = set()
    for name in os.listdir(available_dir):
        source = os.path.join(available_dir, name)
        if not name.endswith('.yaml') or not os.path.isfile(source):
            continue
        yaml_names.add(name)
        with open(source, 'r') as f:
            lines = f.read().splitlines()
        if 'kind: Deployment' in lines:
            expected_deployments.add(name)

    for name in yaml_names:
        link_path = os.path.join(active_dir, name)
        source_path = os.path.join(available_dir, name)
        if name in expected_deployments:
            assert os.path.islink(link_path), f"{link_path} is not a symlink."
            assert _points_to(link_path, source_path), (
                f"{link_path} does not point to {source_path}."
            )
        else:
            assert not os.path.lexists(link_path), (
                f"{link_path} should not exist because it is not a Deployment."
            )

    # Retain the original checks for the manifests supplied by the task.
    app1_link = os.path.join(active_dir, 'app1.yaml')
    app3_link = os.path.join(active_dir, 'app3.yaml')
    app2_link = os.path.join(active_dir, 'app2.yaml')
    assert os.path.islink(app1_link), f"{app1_link} is not a symlink."
    assert _points_to(app1_link, os.path.join(available_dir, 'app1.yaml'))
    assert os.path.islink(app3_link), f"{app3_link} is not a symlink."
    assert _points_to(app3_link, os.path.join(available_dir, 'app3.yaml'))
    assert not os.path.exists(app2_link), (
        f"{app2_link} should not exist because it is not a Deployment."
    )


def test_services_json_dependency():
    json_path = '/home/user/services.json'
    assert os.path.isfile(json_path), f"{json_path} is missing."

    with open(json_path, 'r') as f:
        try:
            services = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} is not valid JSON.")

    assert 'operator' in services, "operator block missing in services.json."
    assert services['operator'].get('depends_on') == 'validator', (
        "operator block does not have 'depends_on': 'validator'."
    )


def test_runner_executes_and_recreates_success_log():
    runner_path = '/home/user/runner.py'
    log_path = '/home/user/operator_success.log'

    assert os.path.isfile(runner_path), f"{runner_path} is missing."
    if os.path.lexists(log_path):
        os.unlink(log_path)

    result = subprocess.run(
        [sys.executable, runner_path],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=20,
    )

    assert result.returncode == 0, (
        f"Running {runner_path} failed with exit code {result.returncode}:\n"
        f"{result.stdout}"
    )
    assert os.path.isfile(log_path), (
        f"{log_path} was not generated by running {runner_path}."
    )

    with open(log_path, 'r') as f:
        content = f.read()
    assert "All systems nominal." in content, (
        f"{log_path} does not contain the expected success message."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
