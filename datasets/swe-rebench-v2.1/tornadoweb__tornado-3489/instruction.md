NUL and CR are incorrectly permitted within header values
The HTTP RFCs specify that NUL, CR, and LF bytes are not permitted within HTTP header values. Tornado does not enforce this rule for NUL and CR.
