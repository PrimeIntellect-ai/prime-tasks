#!/bin/bash
# Oracle implementation to extract the specific format
grep -a -o -E '[A-Z]{4}-[0-9]{4}:[0-9]{1,5}'
