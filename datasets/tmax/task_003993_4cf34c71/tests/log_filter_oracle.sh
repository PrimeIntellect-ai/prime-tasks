#!/bin/bash
awk -F',' '$2 == "billing-svc" && $4 > 400 {print $3}'
