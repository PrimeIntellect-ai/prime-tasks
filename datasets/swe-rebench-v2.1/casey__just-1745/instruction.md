`just --unstable --list --unsorted` has weird behavior with includes
The code in https://github.com/casey/just/blob/master/src/justfile.rs#L367-L370 that determines what order recipes will be listed in when not sorted alphabetically depends on the offset of a recipe from the beginning of its file.

E.g. if you have the justfiles:

`justfile`:
```
# newlines


default:
    echo "DEFAULT"

!include ./include.justfile
```

`include.justfile`:
```
alpha:
    echo "ALPHA"

beta:
    echo "BETA"
```

Then the output of `just --unstable --list --unsorted` on latest master is:
```
Available recipes:
    alpha
    default
    beta
```

instead of the `default - alpha - beta` order I'd expect.

https://github.com/casey/just/pull/1739 has a solution for this (albeit not a working test), but it also computes the default recipe in a way different than what https://github.com/casey/just/pull/1740 decided on, so I'm not sure how much of the code from 1739 is useful.
