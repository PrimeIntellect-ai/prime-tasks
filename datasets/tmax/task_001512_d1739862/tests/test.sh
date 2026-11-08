#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import unicodedata
import math
from collections import defaultdict
import pytest

def get_expected_data(raw_path):
    with open(raw_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        raw_data = list(reader)

    # Reshape and Normalize
    long_data = []
    for row in raw_data:
        date = row['Date']
        pid = row['Product_ID']
        nname = unicodedata.normalize('NFKC', row['Product_Name_Local'])

        for region in ['NA', 'EU', 'AS']:
            sales = float(row[f'Sales_{region}']) if row.get(f'Sales_{region}') else 0.0
            temp_str = row.get(f'Temp_{region}', '')
            temp = float(temp_str) if temp_str.strip() else None

            long_data.append({
                'Date': date,
                'Product_ID': pid,
                'Normalized_Name': nname,
                'Region': region,
                'Sales': sales,
                'Temp': temp
            })

    # Sort by Region and Date (to match pandas sort_values)
    # Note: pandas sort_values is stable, we sort by Region then Date
    # Wait, the truth script does: df_long = df_long.sort_values(by=['Region', 'Date'])
    # In pandas, wide_to_long preserves the original row order, then sorts.
    # We will just sort by Region and Date.
    long_data.sort(key=lambda x: (x['Region'], x['Date']))

    # Interpolate Temp within each Region
    regions = ['NA', 'EU', 'AS']
    for region in regions:
        region_rows = [r for r in long_data if r['Region'] == region]
        temps = [r['Temp'] for r in region_rows]

        # Linear interpolation
        n = len(temps)
        i = 0
        while i < n:
            if temps[i] is None:
                j = i
                while j < n and temps[j] is None:
                    j += 1
                if i > 0 and j < n:
                    start_val = temps[i-1]
                    end_val = temps[j]
                    steps = j - i + 1
                    step_size = (end_val - start_val) / steps
                    for k in range(i, j):
                        temps[k] = start_val + step_size * (k - i + 1)
                i = j
            else:
                i += 1

        for row, t in zip(region_rows, temps):
            if t is not None:
                row['Temp'] = round(t, 2)
            else:
                row['Temp'] = None

    # Aggregate
    agg = defaultdict(lambda: {'Sales': 0.0, 'Temps': []})
    for row in long_data:
        key = (row['Region'], row['Product_ID'], row['Normalized_Name'])
        agg[key]['Sales'] += row['Sales']
        if row['Temp'] is not None:
            agg[key]['Temps'].append(row['Temp'])

    expected = []
    for key, vals in agg.items():
        region, pid, nname = key
        total_sales = vals['Sales']
        avg_temp = sum(vals['Temps']) / len(vals['Temps']) if vals['Temps'] else float('nan')
        expected.append({
            'Region': region,
            'Product_ID': pid,
            'Normalized_Name': nname,
            'Total_Sales': total_sales,
            'Avg_Temp': round(avg_temp, 2) if not math.isnan(avg_temp) else None
        })

    # Sort
    expected.sort(key=lambda x: (x['Region'], -x['Total_Sales'], x['Product_ID']))
    return expected

def test_summary_file_exists():
    assert os.path.exists('/home/user/summary.csv'), "The summary.csv file was not created."

def test_summary_file_content():
    raw_path = '/home/user/raw_sales.csv'
    summary_path = '/home/user/summary.csv'

    if not os.path.exists(raw_path) or not os.path.exists(summary_path):
        pytest.skip("Required files not found.")

    expected_data = get_expected_data(raw_path)

    with open(summary_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        actual_data = list(reader)

    expected_columns = ['Region', 'Product_ID', 'Normalized_Name', 'Total_Sales', 'Avg_Temp']
    assert reader.fieldnames == expected_columns, f"Columns do not match. Expected {expected_columns}, got {reader.fieldnames}"

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} rows, got {len(actual_data)} rows."

    for i, (act, exp) in enumerate(zip(actual_data, expected_data)):
        assert act['Region'] == exp['Region'], f"Row {i}: Region mismatch."
        assert act['Product_ID'] == exp['Product_ID'], f"Row {i}: Product_ID mismatch."
        assert act['Normalized_Name'] == exp['Normalized_Name'], f"Row {i}: Normalized_Name mismatch."

        act_sales = float(act['Total_Sales'])
        assert math.isclose(act_sales, exp['Total_Sales'], rel_tol=1e-5), f"Row {i}: Total_Sales mismatch. Expected {exp['Total_Sales']}, got {act_sales}"

        if exp['Avg_Temp'] is not None:
            act_temp = float(act['Avg_Temp'])
            assert math.isclose(act_temp, exp['Avg_Temp'], abs_tol=0.02), f"Row {i}: Avg_Temp mismatch. Expected {exp['Avg_Temp']}, got {act_temp}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
