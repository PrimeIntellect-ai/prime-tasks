import sys
import math

def clean(row):
    parts = row.split(',')
    if len(parts) != 4: return "00000000,0.0,Unknown,"

    # Rule 1
    try:
        id_val = str(int(parts[0])).zfill(8)
    except:
        id_val = "00000000"

    # Rule 2
    try:
        temp_val = float(parts[1])
        if math.isnan(temp_val):
            temp_str = "0.0"
        else:
            temp_str = f"{temp_val:.1f}"
    except:
        temp_str = "0.0"

    # Rule 3
    stat = parts[2].strip()
    if stat == 'A':
        stat_str = 'Active'
    elif stat == 'I':
        stat_str = 'Inactive'
    else:
        stat_str = 'Unknown'

    # Rule 4
    date_str = parts[3]

    return f"{id_val},{temp_str},{stat_str},{date_str}"

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(clean(sys.argv[1]))
