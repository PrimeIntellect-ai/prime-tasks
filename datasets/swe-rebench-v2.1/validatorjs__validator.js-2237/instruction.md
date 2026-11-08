Non breaking space bypass email validation
"test test@test.com" won't pass since it's a regular space (0x0020), but "test test@test.com" will pass since it's a non breaking space (0x00A0).

In fact, /\s/ regex pattern is not checking for non breaking spaces.

Here is a thread about it: https://stackoverflow.com/questions/31790440/regex-to-replace-no-break-space
