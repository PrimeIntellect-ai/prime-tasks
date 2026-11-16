instead of panicking on a stranger short options - parse them
Current code would split `-Obits=2048` into `Obits` and `2048` which fails, splitting it into `O` and `bits=2048` is strictly more useful.


see https://github.com/pacak/bpaf/discussions/120
