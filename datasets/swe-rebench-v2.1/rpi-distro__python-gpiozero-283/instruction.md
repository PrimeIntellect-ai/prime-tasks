Remote pin issue caused by pi_info
I think the pigpio remote pin access is a really interesting prospect. Trying the brilliant demo in the docs of creating an instance of a pin object remotely on a Pi from another machine currently fails when run on a computer that's not a Pi due to the exception raised in `pi_info()`. There needs to be a way of it detecting the return value of `pi_info()` on the host Pi, or it to fall back on a sensible default.

Similarly, will there be an issue if an unknown Pi (future product or unknown revision) is used? Or does the code in pi_info() rely on the host running Raspbian? Would it work on Ubuntu MATE, for example?
