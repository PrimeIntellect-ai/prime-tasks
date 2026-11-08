ArgsToStrings misses delimiter with one-character args
> MONITOR + a,b,c
> :oragono.test 731 hi a,b,c
> MONITOR L
> :oragono.test 732 hi ab,c
> :oragono.test 733 hi :End of MONITOR list
> MONITOR S
> :oragono.test 731 hi ab,c
