Row dropped with pandas read_csv on linux
**Describe the bug**
When using pyfakefs with pandas, sometimes a single row is dropped on write / read. This only occurs on linux systems (tested with ubuntu laptop), with no issue on Windows. Totally understand if this issue is out of scope - as there are known issues with pandas listed in the docs!

**How To Reproduce**
Run the following on a linux system via pytest:
```
import pandas as pd

def test_minimal_example(fs):

    fs.create_dir("/TEST")

    n_rows = 46
    df = pd.DataFrame({
     "abcdefghlmnopqrst": [1]*n_rows,
     "abcdef": [1]*n_rows,
     "abcdefghijklm": ['ABCD']*n_rows,
     "abcdefghijklmnopqrstuvw": [pd.Timestamp('2023-06-13 02:24:46.996459+0000', tz='UTC')]*n_rows,
     "abcdefghijklmnopqrstuv": [pd.Timestamp('2023-06-02 09:20:20+0000', tz='UTC')]*n_rows,
     "abcdefghijklmnopqr": [pd.NaT]*35 + [pd.Timestamp('2023-06-15 18:00:00+0000', tz='UTC')]*11,
     "abcdefghijklmn": ['ABCDEFGHIJ']*n_rows,
     "abcdefghlmnopqr": ['ABCDEFG']*n_rows,
     "abcdefghijklmnopqrstuvwxyz": ['ABCD']*n_rows,
     "abcdefghijklmnopqrstuvwxy": ['ABCDEFGHIJK', None]*(int(n_rows/2)),
     "abcdefghij": ['ABC']*n_rows,
     "abcdefghi": [pd.Timestamp('2017-01-22 08:01:44.253136+0000', tz='UTC')]*n_rows,
     "abcdefghijk": [pd.Timestamp('2018-10-11 12:03:31.663658+0000', tz='UTC')]*n_rows
    })
    df.to_csv("/TEST/test.csv", index=False)

    read_df = pd.read_csv("/TEST/test.csv")
    assert len(read_df) == len(df)
```
Once read, the dataframe will drop one row (from 46 to 45). Changing pretty much anything about this dataframe e.g. names of columns, number of rows etc... will lead to this test passing.

**Your environment**
I'm running on WSL, but a colleague had the same issue on their ubuntu system:
```
Linux-5.15.167.4-microsoft-standard-WSL2-x86_64-with-glibc2.35
Python 3.11.11 (main, Dec 11 2024, 16:28:39) [GCC 11.2.0]
pyfakefs 5.7.4
pytest 8.3.4
```
