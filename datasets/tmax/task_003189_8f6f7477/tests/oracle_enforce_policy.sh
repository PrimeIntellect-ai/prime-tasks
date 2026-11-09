#!/bin/bash
INPUT="$1"
if [[ "$INPUT" == *"redirect_uri=http://"* ]] || [[ "$INPUT" == *"redirect_uri=https://"* ]]; then
    echo "CWE-601"
elif [[ "$INPUT" == *"<script>"* ]] || [[ "$INPUT" == *"javascript:"* ]]; then
    echo "CWE-79"
elif [[ "$INPUT" == *"X-Admin-Access: true"* ]] && [[ "$INPUT" == *"Cookie: bypass="* ]]; then
    echo "AUTH_BYPASS"
else
    echo "SAFE"
fi
