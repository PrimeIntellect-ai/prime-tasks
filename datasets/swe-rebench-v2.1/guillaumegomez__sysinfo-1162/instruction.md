Make `Process::root` return an `Option`
It can be a non-available information and as such, should return an `Option` rather than an empty `Path`. (For example it's empty on mac)
