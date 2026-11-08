Machine locked attribute is missing
At the moment both lock() and unlock() functions have been implemented for machines. While these methods work without any problem I would like to be able to check the locked status before calling them.

The actual case is that I want to fetch the power parameters for a deployed machine but I do not have the permission to do so. This is happening because we are locking our deployed machines to avoid any action happen on them.

Inside one of my scripts, I want to unlock a machine, fetch the power parameters and afterwards, lock the machine again. If the locked status was exposed I could call unlock() function only to locked machines.

Extends #211

### Additional contract requirements

- `Machine.locked` is a read-only boolean attribute that exposes the
  machine's locked status from the API payload: `True` when the machine is
  locked and `False` otherwise.
- Assigning to `Machine.locked` raises `AttributeError`.
- Accessing `Machine.locked` when the machine data includes a locked flag
  returns the boolean value without raising. If the machine data does not
  include a locked flag, accessing `Machine.locked` does not raise an
  unexpected error; it may return `None` or `False`, or raise
  `AttributeError`.
