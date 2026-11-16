open() signature is not picked up from typeshed
Probably because at runtime open() pretends to be io.open.
