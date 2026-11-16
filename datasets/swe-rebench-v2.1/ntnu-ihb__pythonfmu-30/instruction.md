Rename internal getters and setters
Rename internal getters and setter which uses \_\_XXX__ method names to __XXX

### Additional contract requirements

The typed FMI variable accessors on `Fmi2Slave` are named `get_integer`, `get_real`, `get_boolean`, and `get_string` for reads, and `set_integer`, `set_real`, `set_boolean`, and `set_string` for writes. Each getter takes a list of value references and returns their current values as a list in the requested order. Each setter takes a list of value references and a corresponding list of values, and updates those variables.
