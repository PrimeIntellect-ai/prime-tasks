#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import pytest

ANOMALIES_PATH = '/home/user/anomalies.json'
CSV_PATH = '/home/user/server_logs.csv'
INTEL_PATH = '/home/user/threat_intel.json'
TEMPLATE_PATH = '/home/user/report_template.jinja'


def load_expected():
    try:
        with open(CSV_PATH, 'r', newline='') as f:
            rows = list(csv.DictReader(f))
        with open(INTEL_PATH, 'r') as f:
            threat_intel = json.load(f)
    except Exception as e:
        pytest.fail(f'Failed to read source data: {e}')

    true_ids = set()
    expected = []
    changepoint_hit = False
    for i, row in enumerate(rows):
        if not changepoint_hit and i >= 4:
            window = rows[i-4:i+1]
            avg = sum(int(r['response_time']) for r in window) / 5.0
            if avg > 850:
                changepoint_hit = True

        if changepoint_hit:
            record = {
                'id': int(row['id']),
                'timestamp': row['timestamp'],
                'ip_address': row['ip_address'],
                'response_time': int(row['response_time']),
                'actor_group': threat_intel.get(row['ip_address'], 'Unknown'),
            }
            expected.append(record)
            true_ids.add(record['id'])

    return expected, true_ids


def load_agent_data():
    try:
        with open(ANOMALIES_PATH, 'r') as f:
            return json.load(f)
    except Exception as e:
        pytest.fail(f'Failed to read {ANOMALIES_PATH}: {e}')


def canonicalize(item):
    assert isinstance(item, dict), 'Each item in anomalies.json must be a JSON object.'
    required = {'id', 'timestamp', 'ip_address', 'response_time', 'actor_group'}
    assert set(item.keys()) == required, f'Output object must contain exactly {sorted(required)}: {item}'
    try:
        item_id = int(item['id'])
        response_time = int(item['response_time'])
    except (TypeError, ValueError):
        pytest.fail(f"Invalid id or response_time value in output: {item}")
    return {
        'id': item_id,
        'timestamp': item['timestamp'],
        'ip_address': item['ip_address'],
        'response_time': response_time,
        'actor_group': item['actor_group'],
    }


def render_template(template, anomalies):
    match = re.search(r'{%\s*for\s+a\s+in\s+anomalies\s*%}(.*?){%\s*endfor\s*%}', template, re.DOTALL)
    assert match, 'The supplied report template has an unsupported or missing anomalies loop.'
    block = match.group(1)

    def render_block(record):
        def replace_var(var_match):
            return str(record[var_match.group(1)])
        rendered = re.sub(
            r'{{\s*a\.(id|timestamp|ip_address|response_time|actor_group)\s*}}',
            replace_var,
            block,
        )
        assert '{{' not in rendered and '{%' not in rendered, 'Unrendered template expression remains.'
        return rendered

    return template[:match.start()] + ''.join(render_block(a) for a in anomalies) + template[match.end():]


def test_anomalies_json_exists():
    assert os.path.isfile(ANOMALIES_PATH), f'{ANOMALIES_PATH} does not exist.'


def test_f1_score_and_structure_and_enrichment():
    agent_data = load_agent_data()
    assert isinstance(agent_data, list), f'{ANOMALIES_PATH} must be a JSON array.'

    canonical = [canonicalize(item) for item in agent_data]
    agent_ids = {item['id'] for item in canonical}
    expected, true_ids = load_expected()

    # Preserve the original F1 assertion.
    tp = len(agent_ids & true_ids)
    fp = len(agent_ids - true_ids)
    fn = len(true_ids - agent_ids)
    if tp == 0:
        f1 = 0.0
    else:
        precision = tp / (tp + fp)
        recall = tp / (tp + fn)
        f1 = 2 * (precision * recall) / (precision + recall)
    assert f1 >= 0.95, f'F1 Score is {f1:.4f}, which is below the threshold of 0.95. True anomalies count: {len(true_ids)}, Detected: {len(agent_ids)}'

    assert len(canonical) == len(agent_ids), 'anomalies.json contains duplicate anomaly IDs.'
    assert agent_ids == true_ids, f'Anomaly IDs are not exact. Expected {sorted(true_ids)}, got {sorted(agent_ids)}'

    expected_by_id = {item['id']: item for item in expected}
    for item in canonical:
        assert item == expected_by_id[item['id']], f'Incorrect extracted or enriched fields for ID {item["id"]}: {item}'


def test_generated_report_matches_template():
    expected, _ = load_expected()
    try:
        with open(TEMPLATE_PATH, 'r') as f:
            template = f.read()
    except Exception as e:
        pytest.fail(f'Failed to read report template: {e}')
    expected_report = render_template(template, expected).rstrip('\n')

    excluded = {
        os.path.realpath(ANOMALIES_PATH),
        os.path.realpath(CSV_PATH),
        os.path.realpath(INTEL_PATH),
        os.path.realpath(TEMPLATE_PATH),
    }
    candidates = []
    for root, _, files in os.walk('/home/user'):
        for name in files:
            path = os.path.join(root, name)
            real = os.path.realpath(path)
            lower = name.lower()
            if real in excluded or not os.path.isfile(path):
                continue
            if 'report' not in lower and not lower.endswith(('.txt', '.md')):
                continue
            try:
                if os.path.getsize(path) > 1024 * 1024:
                    continue
                with open(path, 'r') as f:
                    content = f.read().rstrip('\n')
            except (OSError, UnicodeError):
                continue
            candidates.append(path)
            if content == expected_report:
                return

    pytest.fail('No generated report text matching report_template.jinja was found under /home/user. Checked: ' + repr(candidates))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
