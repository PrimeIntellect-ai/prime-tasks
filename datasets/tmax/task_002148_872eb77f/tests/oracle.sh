#!/bin/bash
CRITICAL_CWE="CWE-78"
TRUSTED_HASH="88d4266fd4e6338d13b845fcf289579d209c897823b9217da3e161936f031589"

while IFS='|' read -r filepath filehash cwe message || [ -n "$filepath" ]; do
    if [ "$cwe" = "CWE-000" ]; then
        echo "CONFIG_ERROR|$filepath"
    elif [ "$filehash" != "$TRUSTED_HASH" ]; then
        echo "INTEGRITY_VIOLATION|$filepath"
    elif [ "$cwe" = "$CRITICAL_CWE" ]; then
        echo "CWE_ALERT|$filepath|$message"
    else
        echo "COMPLIANT|$filepath"
    fi
done
