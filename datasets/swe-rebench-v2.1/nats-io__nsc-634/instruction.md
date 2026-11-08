Add an option to create a scoped signing-key in one command
### What motivated this proposal?

Currently, to create a scoped signing-key, one hase to call `nsc --sk generate`, note the (non machine parseable) ouput, then call the command `nsc --sk KEYJUSTCREATED --role blah`.


### What is the proposed change?

Allow the use of the `--role` parameter when using `nsc --sk generate`, so the key is immediately scoped, and can be referred by its role further in the key deployment process.

### Who benefits from this change?

Using decentralized authentication for NATS is a very good feature. Scoped signing-keys is even better.
The current way the creation is implemented is error prone, because you either depend on one's copy/paste skills, or parsing an stdout output which you have no warranty that it won't change in the future.

### What alternatives have you evaluated?

I need to check the generate return code, and if it is valid, grep / awk / sed the output to get the key argument to pass to the next nsc call. Very inefficient.
