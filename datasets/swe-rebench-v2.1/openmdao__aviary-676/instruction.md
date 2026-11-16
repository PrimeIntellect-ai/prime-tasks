Some floats in the csv file are processed as integers if they are whole numbers (like 1.0).
### Description

This is documented in utils/functions.py : convert_strings_to_data

        try:
            # if the value is a number store it as a float or an int as appropriate
            # BUG this returns floats that can be converted to int (e.g. 1.0) as an int (1), even if the variable requires floats
            value_list[ii] = int(float(dat)) if float(
                dat).is_integer() else float(dat)



### Example

Setting Aircraft.Wing.AIRFOIL_TECHNOLOGY to 1.0 in a csv file will trigger this.

### Aviary Version

0.9.9-dev

### Relevant environment information

_No response_
