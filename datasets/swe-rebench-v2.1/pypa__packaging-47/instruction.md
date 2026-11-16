==0.1.* doesn't match 0.1+upstream.2
As in the title, `==0.1.*` doesn't match the version `0.1+upstream.2`. I discovered this as a result of specifying a requirement `~=0.1.0`, and getting `0.1` instead of `0.1+upstream.2`. I can produce a reproducing example if necessary.
