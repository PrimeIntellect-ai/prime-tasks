All Java identifiers are not supported
Fixed by #544

### Additional contract requirements

- Template variable identifiers must support Unicode letters, including letters from non-ASCII scripts. This requirement does not extend to every character permitted in a Java identifier; identifiers must still follow Pebble's identifier syntax, including not starting with a digit.
