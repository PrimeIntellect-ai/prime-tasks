#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re

def test_services_enabled_symlinks():
    enabled_dir = '/home/user/services-enabled'
    assert os.path.isdir(enabled_dir), f"Directory {enabled_dir} is missing"

    web_link = os.path.join(enabled_dir, 'web.json')
    api_link = os.path.join(enabled_dir, 'api.json')
    db_link = os.path.join(enabled_dir, 'db.json')

    assert os.path.islink(web_link), f"{web_link} is not a symlink"
    assert os.readlink(web_link) == '/home/user/services-available/web.json', f"{web_link} points to wrong target"

    assert os.path.islink(api_link), f"{api_link} is not a symlink"
    assert os.readlink(api_link) == '/home/user/services-available/api.json', f"{api_link} points to wrong target"

    assert not os.path.exists(db_link), f"{db_link} should not exist in {enabled_dir}"

def test_pipeline_script():
    pipeline = '/home/user/pipeline.sh'
    assert os.path.isfile(pipeline), f"{pipeline} is missing"
    assert os.access(pipeline, os.X_OK), f"{pipeline} is not executable"

def test_monitor_script_and_symlink():
    monitor_py = '/home/user/monitor.py'
    bin_dir = '/home/user/bin'
    monitor_link = os.path.join(bin_dir, 'monitor')

    assert os.path.isfile(monitor_py), f"{monitor_py} is missing"
    assert os.access(monitor_py, os.X_OK), f"{monitor_py} is not executable"

    assert os.path.isdir(bin_dir), f"Directory {bin_dir} is missing"
    assert os.path.islink(monitor_link), f"{monitor_link} is not a symlink"
    assert os.readlink(monitor_link) == monitor_py, f"{monitor_link} does not point to {monitor_py}"

def test_report_txt():
    report = '/home/user/report.txt'
    assert os.path.isfile(report), f"{report} is missing"

    with open(report, 'r') as f:
        content = f.read()

    # No TCP service is provided on port 8080, so web should be DOWN.
    assert re.search(r'\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} JST\] Service web on port 8080 is DOWN\. Home disk usage: \d+%', content), \
        "report.txt does not contain the correct log for web service (expected DOWN with JST timezone and disk usage)"

    # No TCP service is provided on port 8081, so api should be DOWN.
    assert re.search(r'\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} JST\] Service api on port 8081 is DOWN\. Home disk usage: \d+%', content), \
        "report.txt does not contain the correct log for api service (expected DOWN with JST timezone and disk usage)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
