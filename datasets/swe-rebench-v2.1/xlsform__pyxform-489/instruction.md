type=calculate with (ignored) label does not show an error when used as trigger
#### Software and hardware versions
pyxform v1.2.1

#### Problem description
Users may accidentally add a label to type=calculate. This label is mostly ignored by pyxform and not present in the Pyxform output. That's all good. However, the helpful error message generation logic introduced in https://github.com/XLSForm/pyxform/issues/452 actually gets fooled by this otherwise ignored label.

#### Steps to reproduce the problem

type | name | label | calculation | trigger
-- | -- | -- | -- | --
calculate | calc2 | calculate item label | 1+1 |
text | text2 | triggered from calc2 | 4+4 | ${calc2}

#### Expected behavior

To output the same pyxform error message as with this form (since they are essentially exactly the same form) :

type | name | label | calculation | trigger
-- | -- | -- | -- | --
calculate | calc2 |  | 1+1 |
text | text2 | triggered from calc2 | 4+4 | ${calc2}

#### Other info

I also considered an alternative solution where a type=calculate with a label gets a warning. However, since that should probably be a warning and not an error, I think we would still need the above error that prevents the XForm from being created.
