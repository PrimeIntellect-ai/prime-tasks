Process manager instance should log and ignore unexpected info messages
A process manager instance process will crash if it receives an unexpected info message. Instead of crashing, a catch-all `handle_info/2` callback should log the message and ignore it.

It is also worth considering whether to allow a process manager to handle info messages by implementing its own optional `handle_info/2` callback function.
