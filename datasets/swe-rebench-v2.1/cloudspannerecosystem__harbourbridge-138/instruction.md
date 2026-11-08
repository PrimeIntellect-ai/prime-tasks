Handle data conversion of non-boolean values for MySQL TINYINT(1)/BOOLEAN
NOTE: TINYINT(1) is a synonym for BOOL and BOOLEAN.

MySQL does not require values for BOOLEAN to actually be boolean values.
Instead, it allows any legal value for tinyint to be stored in a BOOLEAN i.e. -128 to 127.

At the moment, HarbourBridge generates an error and rejects rows where boolean columns have non-boolean values.

Proposed resolution: instead of generating an error, convert integer values to booleans using the standard heuristic: 0 is false and non-zero is true.
