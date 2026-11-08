#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import runpy
import subprocess
import sys
import types
import urllib.error
import urllib.request
import uuid

import pandas as pd
import pytest

sys.path.insert(0, "/home/user/app")

try:
    from sanitizer import process_translations, write_stratified_sample
except ImportError:
    pass


def _assert_rows(df, expected):
    assert isinstance(df, pd.DataFrame)
    assert {'string_id', 'context_tag', 'translation'}.issubset(df.columns)
    assert len(df) == len(expected)
    actual = {
        str(row['string_id']): (str(row['context_tag']), str(row['translation']))
        for _, row in df.iterrows()
    }
    assert actual == expected


def test_sanitizer_adversarial_corpus():
    clean_dir = "/home/user/corpus/clean/"
    evil_dir = "/home/user/corpus/evil/"
    base_csv_path = "/home/user/app/base_en.csv"

    assert os.path.exists(clean_dir), f"Clean directory missing: {clean_dir}"
    assert os.path.exists(evil_dir), f"Evil directory missing: {evil_dir}"
    assert os.path.exists(base_csv_path), f"Base CSV missing: {base_csv_path}"

    clean_failed = []
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.csv')]
    for f in clean_files:
        path = os.path.join(clean_dir, f)
        try:
            df = process_translations(path, base_csv_path)
            if not isinstance(df, pd.DataFrame) or len(df) == 0:
                clean_failed.append(f)
        except Exception:
            clean_failed.append(f)

    assert not clean_failed, (
        f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: "
        + ', '.join(clean_failed)
    )

    xss = process_translations(os.path.join(evil_dir, "xss_payload.csv"), base_csv_path)
    _assert_rows(xss, {'msg_success': ('message', 'Success!')})

    malformed = process_translations(
        os.path.join(evil_dir, "malformed_newlines.csv"), base_csv_path
    )
    _assert_rows(malformed, {'btn_submit': ('button', 'Soumettre')})


def test_sanitizer_generated_mixed_input(tmp_path):
    token = uuid.uuid4().hex[:10]
    ids = {name: f"{token}_{name}" for name in (
        'valid', 'empty', 'missing', 'script', 'brace', 'newline', 'tail'
    )}

    base = tmp_path / f"base_{token}.csv"
    upload = tmp_path / f"upload_{token}.csv"

    base_rows = [
        (ids['valid'], 'nav', 'English valid'),
        (ids['empty'], 'nav', 'English empty'),
        (ids['missing'], 'message', 'English missing'),
        (ids['script'], 'message', 'English script'),
        (ids['brace'], 'button', 'English brace'),
        (ids['newline'], 'button', 'English newline'),
        (ids['tail'], 'footer', 'English tail'),
    ]
    base.write_text(
        'string_id|context_tag|text\n' +
        ''.join(f'{sid}|{ctx}|{text}\n' for sid, ctx, text in base_rows),
        encoding='utf-8'
    )

    upload.write_text(
        'string_id|translation\n'
        f"{ids['valid']}|Translated valid\n"
        f"{ids['empty']}|\n"
        f"{ids['script']}|<script>alert(1)</script>\n"
        f"{ids['brace']}|Hello {{user\n"
        f"{ids['newline']}|Broken first line\n"
        'unquoted continuation text\n'
        f"{ids['tail']}|Translated tail\n",
        encoding='utf-8'
    )

    df = process_translations(str(upload), str(base))
    _assert_rows(df, {
        ids['valid']: ('nav', 'Translated valid'),
        ids['empty']: ('nav', 'English empty'),
        ids['missing']: ('message', 'English missing'),
        ids['tail']: ('footer', 'Translated tail'),
    })


def test_write_stratified_sample(tmp_path):
    df = pd.DataFrame({
        'string_id': ['s1', 's2', 's3', 's4', 's5'],
        'context_tag': ['nav', 'nav', 'nav', 'btn', 'btn'],
        'translation': ['t1', 't2', 't3', 't4', 't5']
    })

    out_path = str(tmp_path / "sample.json")
    write_stratified_sample(df, out_path)

    assert os.path.exists(out_path), "write_stratified_sample did not create the output JSON file"

    with open(out_path, 'r') as f:
        data = json.load(f)

    if isinstance(data, dict) and 'context_tag' in data:
        df_out = pd.read_json(out_path)
    else:
        df_out = pd.read_json(out_path, orient='records' if isinstance(data, list) else None)

    counts = df_out['context_tag'].value_counts()
    assert counts.get('nav', 0) == 2, "Expected exactly 2 samples for 'nav' context"
    assert counts.get('btn', 0) == 2, "Expected exactly 2 samples for 'btn' context"


def test_app_uses_redis_environment(monkeypatch):
    calls = []

    class DummyRedis:
        def __init__(self, *args, **kwargs):
            calls.append(('Redis', args, kwargs))

        @classmethod
        def from_url(cls, url, *args, **kwargs):
            calls.append(('from_url', (url,) + args, kwargs))
            return cls.__new__(cls)

        def ping(self):
            return True

        def __getattr__(self, name):
            return lambda *args, **kwargs: None

    fake_redis = types.ModuleType('redis')
    fake_redis.Redis = DummyRedis

    def from_url(url, *args, **kwargs):
        calls.append(('from_url', (url,) + args, kwargs))
        return DummyRedis.__new__(DummyRedis)

    fake_redis.from_url = from_url
    monkeypatch.setitem(sys.modules, 'redis', fake_redis)

    host = f"redis-{uuid.uuid4().hex}.invalid"
    port = '16379'
    monkeypatch.setenv('REDIS_HOST', host)
    monkeypatch.setenv('REDIS_PORT', port)
    runpy.run_path('/home/user/app/app.py', run_name='verifier_app_import')

    def uses_values(call):
        _, args, kwargs = call
        if str(kwargs.get('host')) == host and str(kwargs.get('port')) == port:
            return True
        if len(args) >= 2 and str(args[0]) == host and str(args[1]) == port:
            return True
        return any(host in str(value) and port in str(value) for value in args)

    assert calls, "app.py did not construct a Redis client"
    assert any(uses_values(call) for call in calls), (
        "Redis client must use REDIS_HOST and REDIS_PORT environment values"
    )


def test_app_redis_client_connectivity(monkeypatch):
    import redis

    monkeypatch.setenv('REDIS_HOST', '127.0.0.1')
    monkeypatch.setenv('REDIS_PORT', '6379')
    namespace = runpy.run_path('/home/user/app/app.py', run_name='verifier_app_connectivity')
    clients = [value for value in namespace.values() if isinstance(value, redis.Redis)]
    assert clients, "app.py must retain a configured Redis client"
    assert any(client.ping() for client in clients), "The app's Redis client cannot reach Redis"


def test_nginx_configuration():
    config_path = '/home/user/app/nginx.conf'
    assert os.path.isfile(config_path)
    result = subprocess.run(
        ['nginx', '-t', '-c', config_path], capture_output=True, text=True
    )
    assert result.returncode == 0, result.stdout + result.stderr

    config = open(config_path, encoding='utf-8').read()
    assert re.search(r'\blisten\s+8080\s*;', config), "Nginx must listen on port 8080"
    assert re.search(r'\blocation\s+(?:\^~\s+)?/api/', config), (
        "Nginx must define a /api/ location"
    )
    assert re.search(
        r'\bproxy_pass\s+http://127\.0\.0\.1:5000(?:/)?\s*;', config
    ), "The /api/ route must proxy to Flask on 127.0.0.1:5000"


def test_services_composition():
    # Preserve the original Nginx -> Flask routing assertion.
    url = "http://127.0.0.1:8080/api/"

    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            status = response.getcode()
            assert status in [200, 400, 404, 405], f"Unexpected status code: {status}"
    except urllib.error.HTTPError as e:
        assert e.code in [200, 400, 404, 405], f"Unexpected HTTP error code: {e.code}"
    except urllib.error.URLError:
        pytest.fail("Nginx is not proxying to Flask correctly on port 8080")

    direct = urllib.request.Request(
        'http://127.0.0.1:5000/api/upload', data=b'', method='POST'
    )
    proxied = urllib.request.Request(
        'http://127.0.0.1:8080/api/upload', data=b'', method='POST'
    )
    with urllib.request.urlopen(direct, timeout=2) as direct_response:
        direct_status = direct_response.getcode()
        direct_body = direct_response.read()
    with urllib.request.urlopen(proxied, timeout=2) as proxied_response:
        assert proxied_response.getcode() == direct_status
        assert proxied_response.read() == direct_body
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
