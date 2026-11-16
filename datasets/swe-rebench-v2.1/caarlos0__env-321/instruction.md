Non-existing variable of type slice of structs is mapped to an empty slice instead of nil
Hey there

Thanks for your awesome library :+1:

I wanted to update to v11.2.0 and I noticed that the recent change (https://github.com/caarlos0/env/pull/312) changed the semantics regarding slices of structs. The problem is that a non-existing of type `[]someStruct` is mapped to an empty slice instead of the prior behavior (as well as with slices of primitive types) where it is mapped to `nil`.
