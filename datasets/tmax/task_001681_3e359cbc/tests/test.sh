#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from datetime import datetime, timedelta, timezone

import pytest
import redis
import requests

BASE_URL = "http://127.0.0.1:8080"
OUTPUT = "/home/user/processed_metrics.json"
TOKEN = {"Authorization": "Bearer loc-token-99"}
START = datetime(2023, 10, 1, tzinfo=timezone.utc)
HOURS = [(START + timedelta(hours=i)).strftime("%Y-%m-%dT%H:00:00Z") for i in range(25)]

# Deliberately different irregular observations from the image's seed data. Expected
# answers are derived here, so fixed responses for the original two points cannot pass.
EVENTS = [
    {"timestamp": "2023-10-01T00:37:00Z", "lang": "es", "strings_translated": 11, "missing_keys": 51},
    {"timestamp": "2023-10-01T04:12:00Z", "lang": "es", "strings_translated": 73, "missing_keys": 19},
    {"timestamp": "2023-10-01T17:58:00Z", "lang": "es", "strings_translated": 405, "missing_keys": 3},
    {"timestamp": "2023-10-01T02:41:00Z", "lang": "fr", "strings_translated": 26, "missing_keys": 62},
    {"timestamp": "2023-10-01T09:03:00Z", "lang": "fr", "strings_translated": 144, "missing_keys": 15},
    {"timestamp": "2023-10-01T22:29:00Z", "lang": "fr", "strings_translated": 509, "missing_keys": 1},
]


def expected_series(lang):
    observations = sorted(
        (datetime.fromisoformat(e["timestamp"].replace("Z", "+00:00")), e)
        for e in EVENTS if e["lang"] == lang
    )
    result = {}
    for hour_text in HOURS:
        boundary = datetime.fromisoformat(hour_text.replace("Z", "+00:00"))
        eligible = [e for ts, e in observations if ts <= boundary]
        event = eligible[-1] if eligible else observations[0][1]
        strings = event["strings_translated"]
        missing = event["missing_keys"]
        if lang == "es":
            summary = f"Estado ES: {strings} traducidas, {missing} faltantes."
        else:
            summary = f"Statut FR: {strings} traduites, {missing} manquantes."
        result[hour_text] = {
            "strings_translated": strings,
            "missing_keys": missing,
            "summary_text": summary,
        }
    return result


def request(method, path, **kwargs):
    try:
        return requests.request(method, BASE_URL + path, timeout=20, **kwargs)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the Flask app on 127.0.0.1:8080. Is it running?")


def test_unauthorized_trigger():
    response = request("POST", "/trigger_pipeline")
    assert response.status_code == 401, response.text
    response = request("POST", "/trigger_pipeline", headers={"Authorization": "Bearer wrong"})
    assert response.status_code == 401, response.text


def test_authorized_trigger_and_complete_pipeline():
    # Replace Redis input immediately before invoking the API. Also remove any stale
    # output, requiring the authorized endpoint to execute a pipeline that consumes it.
    r = redis.Redis(host="127.0.0.1", port=6379, decode_responses=True)
    try:
        r.ping()
    except redis.RedisError as exc:
        pytest.fail(f"Redis is not available on 127.0.0.1:6379: {exc}")
    r.delete("loc_events")
    for event in EVENTS:
        r.rpush("loc_events", json.dumps(event))
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    response = request("POST", "/trigger_pipeline", headers=TOKEN)
    assert response.status_code == 200, response.text
    assert response.json() == {"status": "success"}
    assert os.path.isfile(OUTPUT), f"{OUTPUT} was not created after triggering the pipeline"

    with open(OUTPUT, encoding="utf-8") as fh:
        document = json.load(fh)

    expected = {lang: expected_series(lang) for lang in ("es", "fr")}
    assert set(document) == {"es", "fr"}
    for lang in ("es", "fr"):
        assert set(document[lang]) == set(HOURS), f"{lang} must contain exactly all 25 hourly timestamps"
        assert document[lang] == expected[lang]

        # Exercise every report point and require it to reflect the generated artifact.
        for hour in HOURS:
            resp = request("GET", "/report", params={"lang": lang, "hour": hour})
            assert resp.status_code == 200, f"{lang} {hour}: {resp.status_code} {resp.text}"
            assert resp.json() == expected[lang][hour], f"incorrect report for {lang} {hour}"


def test_report_not_found():
    resp = request("GET", "/report", params={"lang": "de", "hour": HOURS[0]})
    assert resp.status_code == 404, resp.text
    resp = request("GET", "/report", params={"lang": "es", "hour": "2023-10-03T00:00:00Z"})
    assert resp.status_code == 404, resp.text
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
