#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_es_updates_csv_fetched():
    fetched_csv_path = '/home/user/es_updates.csv'
    assert os.path.isfile(fetched_csv_path), f"File {fetched_csv_path} was not fetched to the working directory."

def test_es_final_json_content_and_format():
    final_json_path = '/home/user/es_final.json'
    assert os.path.isfile(final_json_path), f"File {final_json_path} does not exist."

    expected_data = {
        "checkout": "Checkout now",
        "items_in_cart": "Tienes {count} artículos.",
        "logout_btn": "Cerrar sesión",
        "missing_translation": "This has no Spanish {variable}",
        "welcome_msg": "¡Bienvenido {user_name}, a {app_name}!"
    }

    with open(final_json_path, 'r', encoding='utf-8') as f:
        raw_content = f.read()

    try:
        actual_data = json.loads(raw_content)
    except json.JSONDecodeError:
        assert False, f"File {final_json_path} is not valid JSON."

    assert actual_data == expected_data, f"The merged content in {final_json_path} does not match the expected translations and normalization."

    # Check for formatting: indent of 4 spaces and sorted keys
    expected_raw = json.dumps(expected_data, indent=4, sort_keys=True, ensure_ascii=False)

    # We also allow ensure_ascii=True (which is the default in json.dump)
    expected_raw_ascii = json.dumps(expected_data, indent=4, sort_keys=True)

    # Strip whitespace to handle minor newline differences at EOF
    assert raw_content.strip() == expected_raw.strip() or raw_content.strip() == expected_raw_ascii.strip(), \
        f"The file {final_json_path} is not properly formatted. It must have an indent of 4 spaces and alphabetically sorted keys."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
