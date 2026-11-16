environment override variables are printed to stderr
Reported by eta in #ergo. This almost seems like a debugging print that got left in the release:

https://github.com/ergochat/ergo/blob/c67835ce5c5547df36476adfe18850ff75f4c332/irc/config.go#L1129-L1131

We can't log at level debug because we don't have the actual logger yet. Let's print the variable name but not the value.
