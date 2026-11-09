#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc parallel
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/locales/

    cat << 'EOF' > /home/user/locales/batch1.jsonl
{"msgid": "greeting", "msgstr": "Hello, World\u0021"}
{"msgid": "error_1", "msgstr": "Failure at line \u123G"}
{"msgid": "farewell", "msgstr": "Goodbye\u002E"}
EOF

    cat << 'EOF' > /home/user/locales/batch2.jsonl
{"msgid": "button_ok", "msgstr": "OK"}
{"msgid": "button_cancel", "msgstr": "Cancel\uXYZ1"}
{"msgid": "prompt", "msgstr": "Enter name\u003A"}
{"msgid": "broken", "msgstr": "Broken \u12"}
EOF

    cat << 'EOF' > /home/user/locales/batch3.jsonl
{"msgid": "valid_unicode", "msgstr": "Check \u1A2B \u3C4D"}
{"msgid": "invalid_unicode", "msgstr": "Check \u1A2B \u3C4Z"}
{"msgid": "no_unicode", "msgstr": "Plain text works fine"}
EOF

    chown -R user:user /home/user/locales/
    chmod -R 777 /home/user
