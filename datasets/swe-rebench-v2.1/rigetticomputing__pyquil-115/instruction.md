Unequal length PauliSums raise a warning rather than warn
If two `PauliTerms` are compared with unequal lengths they raise a warning which breaks the control flow- it should just warn the user.
