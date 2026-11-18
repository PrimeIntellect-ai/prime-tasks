#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential make
    pip3 install pytest

    # Install Rust globally
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/cargo/bin:$PATH"
    chmod -R 777 /opt/rust /opt/cargo

    useradd -m -s /bin/bash user || true

    # Create input.json using Python to avoid Apptainer build variable syntax (curly braces)
    python3 -c '
import json
data = [
  {
    "KEY": " WELCOME MSG ",
    "en": "Welcome, {user}!",
    "es": "Bienvenido, " + chr(123) + chr(123) + "user" + chr(125) + chr(125) + "!",
    "fr": None
  },
  {
    "Key": "logout btn",
    "en": "Log out",
    "es": "",
    "fr": "Se déconnecter"
  },
  {
    "key": "ERROR_NOT_FOUND",
    "en": "Item [item_name] was not found.",
    "de": "Artikel " + chr(123) + chr(123) + "item_name" + chr(125) + chr(125) + " nicht gefunden."
  }
]
with open("/home/user/input.json", "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
'

    chmod -R 777 /home/user
