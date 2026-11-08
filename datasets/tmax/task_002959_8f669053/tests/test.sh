#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile
import uuid


def test_anomalies_log_content():
    log_path = '/home/user/finops_output/anomalies.log'
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "[2023-10-01] WARNING: High cost anomaly - Service: RDS, Resource: db-87654321, Cost: $550.00",
        "[2023-10-02] WARNING: High cost anomaly - Service: EC2, Resource: i-12345678, Cost: $600.00",
        "[2023-10-02] WARNING: High cost anomaly - Service: RDS, Resource: db-87654321, Cost: $550.00"
    ]

    for expected in expected_lines:
        assert expected in lines, f"Expected log entry not found: '{expected}'"

    assert len(lines) == 3, f"Expected exactly 3 log entries, found {len(lines)}"


def test_symlinks_created():
    expected_symlinks = {
        '/home/user/finops_output/high_cost/db-87654321/2023-10-01.csv': '/home/user/billing_logs/2023-10-01.csv',
        '/home/user/finops_output/high_cost/db-87654321/2023-10-02.csv': '/home/user/billing_logs/2023-10-02.csv',
        '/home/user/finops_output/high_cost/i-12345678/2023-10-02.csv': '/home/user/billing_logs/2023-10-02.csv'
    }

    for link_path, target_path in expected_symlinks.items():
        assert os.path.islink(link_path), f"Symlink {link_path} does not exist or is not a symlink."
        actual_target = os.readlink(link_path)
        assert actual_target == target_path, f"Symlink {link_path} points to {actual_target}, expected {target_path}."


def test_logrotate_conf():
    conf_path = '/home/user/logrotate.conf'
    assert os.path.isfile(conf_path), f"Logrotate config {conf_path} does not exist."

    with open(conf_path, 'r') as f:
        content = f.read()

    # Check if the block for the anomalies log exists
    assert '/home/user/finops_output/anomalies.log' in content, f"Logrotate config does not specify the correct log file."

    # Check for required directives
    assert re.search(r'\bsize\s+1k\b', content), "Logrotate config missing 'size 1k' directive."
    assert re.search(r'\brotate\s+3\b', content), "Logrotate config missing 'rotate 3' directive."
    assert re.search(r'\bcompress\b', content), "Logrotate config missing 'compress' directive."
    assert re.search(r'\bmissingok\b', content), "Logrotate config missing 'missingok' directive."


def test_processors_execute_on_fresh_inputs():
    processor = '/home/user/process_billing.py'
    organizer = '/home/user/organize_links.sh'
    assert os.path.isfile(processor), f"Python processor {processor} does not exist or is not a file."
    assert os.path.isfile(organizer), f"Link organizer {organizer} does not exist or is not a file."

    billing = '/home/user/billing_logs'
    output = '/home/user/finops_output'
    backup_root = tempfile.mkdtemp(prefix='finops-verifier-')
    billing_backup = os.path.join(backup_root, 'billing_logs')
    output_backup = os.path.join(backup_root, 'finops_output')

    resource_a = 'dynamic-' + uuid.uuid4().hex
    resource_b = 'dynamic-' + uuid.uuid4().hex
    resource_seed = 'dynamic-' + uuid.uuid4().hex
    resource_threshold = 'dynamic-' + uuid.uuid4().hex

    try:
        shutil.move(billing, billing_backup)
        if os.path.lexists(output):
            shutil.move(output, output_backup)
        os.makedirs(billing)
        os.makedirs(output)

        with open(os.path.join(billing, '2041-01-01.csv'), 'w', newline='') as f:
            f.write('date,service,resource_id,cost\n')
            f.write(f'2041-01-01,Compute,{resource_threshold},500.00\n')
            f.write(f'2041-01-01,Database,{resource_a},500.01\n')

        with open(os.path.join(billing, '2041-01-02.csv'), 'w', newline='') as f:
            f.write('date,service,resource_id,cost\n')
            f.write(f'2041-01-02,Analytics,{resource_b},1234.5\n')
            f.write('2041-01-02,Storage,ordinary-resource,12.25\n')

        # This valid pre-existing entry verifies that the processor appends rather than truncates.
        with open(os.path.join(billing, '2041-01-03.csv'), 'w', newline='') as f:
            f.write('date,service,resource_id,cost\n')
            f.write('2041-01-03,Storage,ordinary-seed-row,1.00\n')

        seed_line = f'[2041-01-03] WARNING: High cost anomaly - Service: Seed, Resource: {resource_seed}, Cost: $999.00'
        with open(os.path.join(output, 'anomalies.log'), 'w') as f:
            f.write(seed_line + '\n')

        subprocess.run(['python3', processor], check=True, timeout=20)

        expected_lines = [
            seed_line,
            f'[2041-01-01] WARNING: High cost anomaly - Service: Database, Resource: {resource_a}, Cost: $500.01',
            f'[2041-01-02] WARNING: High cost anomaly - Service: Analytics, Resource: {resource_b}, Cost: $1234.50',
        ]
        with open(os.path.join(output, 'anomalies.log')) as f:
            actual_lines = [line.strip() for line in f if line.strip()]
        assert sorted(actual_lines) == sorted(expected_lines), \
            f'Processor output was {actual_lines!r}, expected {expected_lines!r}'

        subprocess.run(['bash', organizer], check=True, timeout=20)

        expected_links = {
            os.path.join(output, 'high_cost', resource_a, '2041-01-01.csv'):
                os.path.join(billing, '2041-01-01.csv'),
            os.path.join(output, 'high_cost', resource_b, '2041-01-02.csv'):
                os.path.join(billing, '2041-01-02.csv'),
            os.path.join(output, 'high_cost', resource_seed, '2041-01-03.csv'):
                os.path.join(billing, '2041-01-03.csv'),
        }
        for link_path, target_path in expected_links.items():
            assert os.path.islink(link_path), f'Organizer did not create symlink {link_path}'
            assert os.readlink(link_path) == target_path, \
                f'Symlink {link_path} points to {os.readlink(link_path)!r}, expected {target_path!r}'

        threshold_link = os.path.join(output, 'high_cost', resource_threshold, '2041-01-01.csv')
        assert not os.path.lexists(threshold_link), 'A cost equal to 500.00 must not be treated as an anomaly.'
    finally:
        if os.path.lexists(billing):
            if os.path.isdir(billing) and not os.path.islink(billing):
                shutil.rmtree(billing)
            else:
                os.unlink(billing)
        if os.path.lexists(output):
            if os.path.isdir(output) and not os.path.islink(output):
                shutil.rmtree(output)
            else:
                os.unlink(output)
        if os.path.exists(billing_backup):
            shutil.move(billing_backup, billing)
        if os.path.exists(output_backup):
            shutil.move(output_backup, output)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
