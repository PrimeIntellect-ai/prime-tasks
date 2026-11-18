#!/bin/bash
jq -r '.[] | select(.confidence >= 0.80) | "\(.file_id) => \(.status | ascii_upcase)_\(.timestamp).dat"'
