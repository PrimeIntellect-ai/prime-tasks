#!/bin/bash
iconv -f Windows-1252 -t UTF-8 | awk -F':' 'BEGIN{OFS=":"} $2=="CRITICAL" {$2="RESOLVED"; print}'
