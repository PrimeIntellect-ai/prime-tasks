Using __file__ in a PyInstaller environment is not possible
Babel is not working in my projects which are processed with PyInstaller.
The reason for this: the direct access to "`__file__`".

### Additional contract requirements

When running in a PyInstaller-frozen application, Babel must be able to locate and use its required locale and global data files from the usable bundle location, without relying on an unusable `__file__` path.
