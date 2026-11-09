#!/bin/bash
decoded=$(echo "$1" | base64 -d 2>/dev/null)
if [[ "$decoded" == *"<script>"* ]] || [[ "$decoded" == *"javascript:"* ]] || [[ "$decoded" == *"onerror="* ]]; then
    echo "REJECT_XSS"
elif [[ "$2" != /var/www/uploads/* ]] || [[ "$2" == *".."* ]]; then
    echo "REJECT_PATH"
else
    echo "ACCEPT"
fi
