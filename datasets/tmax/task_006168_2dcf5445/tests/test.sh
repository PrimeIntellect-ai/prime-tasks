#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import json
import os
import secrets
import shutil
import socket
import subprocess
import tempfile


def test_config_corrected_and_directory_created():
    config_path = '/home/user/config/app_services.ini'
    assert os.path.exists(config_path), f"Configuration file {config_path} is missing."

    config = configparser.ConfigParser()
    config.read(config_path)

    assert 'service_gamma' in config, "Section [service_gamma] is missing in the config."
    expected_dir = '/home/user/logs/service_gamma'
    actual_dir = config['service_gamma'].get('log_dir', '').strip()

    assert actual_dir == expected_dir, f"Expected service_gamma log_dir to be {expected_dir}, but got {actual_dir}."
    assert os.path.isdir(expected_dir), f"The directory {expected_dir} was not created."


def test_capacity_report_json():
    report_path = '/home/user/capacity_report.json'
    assert os.path.exists(report_path), f"The report file {report_path} was not created."

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {report_path} does not contain valid JSON."

    assert 'active_port' in report, "The 'active_port' key is missing from the report."
    assert report['active_port'] == 9002, f"Expected active_port to be 9002, but got {report['active_port']}."

    assert 'storage_usage_bytes' in report, "The 'storage_usage_bytes' key is missing from the report."
    usage = report['storage_usage_bytes']

    assert usage.get('service_alpha') == 2548, f"Expected service_alpha usage to be 2548, got {usage.get('service_alpha')}."
    assert usage.get('service_beta') == 4096, f"Expected service_beta usage to be 4096, got {usage.get('service_beta')}."
    assert usage.get('service_gamma') == 0, f"Expected service_gamma usage to be 0, got {usage.get('service_gamma')}."


def test_log_rotation_effects():
    # service_alpha
    alpha_access_log = '/home/user/logs/service_alpha/access.log'
    alpha_access_archive = '/home/user/logs/service_alpha/access.log.archive'
    alpha_error_log = '/home/user/logs/service_alpha/error.log'
    alpha_error_archive = '/home/user/logs/service_alpha/error.log.archive'

    assert os.path.exists(alpha_access_archive), f"Archive file {alpha_access_archive} was not created."
    assert os.path.getsize(alpha_access_archive) == 2048, "The access.log.archive file should be 2048 bytes."
    assert os.path.exists(alpha_access_log), f"The new empty file {alpha_access_log} was not created."
    assert os.path.getsize(alpha_access_log) == 0, f"The new {alpha_access_log} file should be 0 bytes."

    assert not os.path.exists(alpha_error_archive), f"The file {alpha_error_archive} should not exist (size was <= 1024)."
    assert os.path.exists(alpha_error_log), f"The file {alpha_error_log} should still exist."
    assert os.path.getsize(alpha_error_log) == 500, f"The file {alpha_error_log} should remain 500 bytes."

    # service_beta
    beta_worker_log = '/home/user/logs/service_beta/worker.log'
    beta_worker_archive = '/home/user/logs/service_beta/worker.log.archive'

    assert os.path.exists(beta_worker_archive), f"Archive file {beta_worker_archive} was not created."
    assert os.path.getsize(beta_worker_archive) == 4096, "The worker.log.archive file should be 4096 bytes."
    assert os.path.exists(beta_worker_log), f"The new empty file {beta_worker_log} was not created."
    assert os.path.getsize(beta_worker_log) == 0, f"The new {beta_worker_log} file should be 0 bytes."


def test_script_executes_against_runtime_generated_configuration_and_logs():
    script_path = '/home/user/analyze_capacity.py'
    config_path = '/home/user/config/app_services.ini'
    report_path = '/home/user/capacity_report.json'
    gamma_dir = '/home/user/logs/service_gamma'

    assert os.path.isfile(script_path), f"The required Python script {script_path} is missing or is not a file."

    with open(config_path, 'rb') as f:
        original_config = f.read()
    with open(report_path, 'rb') as f:
        original_report = f.read()

    temp_root = tempfile.mkdtemp(prefix='capacity-verifier-', dir='/home/user')
    service_dirs = {
        'service_alpha': os.path.join(temp_root, 'alpha-' + secrets.token_hex(5)),
        'service_beta': os.path.join(temp_root, 'beta-' + secrets.token_hex(5)),
        'service_gamma': gamma_dir,
    }
    for path in service_dirs.values():
        os.makedirs(path, exist_ok=True)

    sockets = []
    generated_paths = []
    records = {}

    try:
        # Reserve two non-listening ports and create one genuinely listening port.
        for should_listen in (False, True, False):
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(('127.0.0.1', 0))
            if should_listen:
                sock.listen(5)
            sockets.append(sock)
        ports = [sock.getsockname()[1] for sock in sockets]

        expected_usage = {}
        for service, directory in service_dirs.items():
            token = secrets.token_hex(8)
            sizes = {
                'large': 1300 + secrets.randbelow(1700),
                'small': 1 + secrets.randbelow(900),
                'boundary': 1024,
            }
            paths = {
                'large': os.path.join(directory, token + '-large.log'),
                'small': os.path.join(directory, token + '-small.log'),
                'boundary': os.path.join(directory, token + '-boundary.log'),
                'ignored': os.path.join(directory, token + '-ignored.txt'),
            }
            contents = {}
            for kind in ('large', 'small', 'boundary'):
                contents[kind] = os.urandom(sizes[kind])
                with open(paths[kind], 'wb') as f:
                    f.write(contents[kind])
            with open(paths['ignored'], 'wb') as f:
                f.write(os.urandom(777))

            generated_paths.extend(paths.values())
            generated_paths.append(paths['large'] + '.archive')
            generated_paths.append(paths['small'] + '.archive')
            generated_paths.append(paths['boundary'] + '.archive')
            expected_usage[service] = sum(sizes.values())
            records[service] = (paths, contents)

        config = configparser.ConfigParser()
        config['service_alpha'] = {'log_dir': service_dirs['service_alpha'], 'port': str(ports[0])}
        config['service_beta'] = {'log_dir': service_dirs['service_beta'], 'port': str(ports[1])}
        config['service_gamma'] = {'log_dir': service_dirs['service_gamma'], 'port': str(ports[2])}
        with open(config_path, 'w') as f:
            config.write(f)

        result = subprocess.run(
            ['python3', script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Executing {script_path} failed with exit code {result.returncode}. "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )

        assert os.path.isfile(report_path), "The script did not create capacity_report.json."
        with open(report_path, 'r') as f:
            report = json.load(f)

        assert set(report.keys()) == {'active_port', 'storage_usage_bytes'}, "The report has an incorrect structure."
        assert report['active_port'] == ports[1], (
            f"Expected the runtime listening port {ports[1]}, got {report['active_port']}."
        )
        assert report['storage_usage_bytes'] == expected_usage, (
            f"Expected runtime-derived usage {expected_usage}, got {report['storage_usage_bytes']}."
        )

        for service, (paths, contents) in records.items():
            archive = paths['large'] + '.archive'
            assert os.path.isfile(archive), f"{service} large log was not archived."
            with open(archive, 'rb') as f:
                assert f.read() == contents['large'], f"{service} archive did not preserve the original bytes."
            assert os.path.isfile(paths['large']) and os.path.getsize(paths['large']) == 0, (
                f"{service} rotated log was not recreated empty."
            )

            for kind in ('small', 'boundary'):
                assert not os.path.exists(paths[kind] + '.archive'), (
                    f"{service} {kind} log should not have been rotated."
                )
                with open(paths[kind], 'rb') as f:
                    assert f.read() == contents[kind], f"{service} {kind} log was modified."
    finally:
        with open(config_path, 'wb') as f:
            f.write(original_config)
        with open(report_path, 'wb') as f:
            f.write(original_report)
        for sock in sockets:
            sock.close()
        for path in generated_paths:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        shutil.rmtree(temp_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
