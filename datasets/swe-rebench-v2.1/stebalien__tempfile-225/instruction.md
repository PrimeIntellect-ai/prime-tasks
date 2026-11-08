The generic version of NamedTempFile can break compilation
The more generic version of `NamedTempFile` introduced in #177 by @jasonwhite can break compilation in some cases without even being involved itself. It seems to happen in some cases with generic where it will turn into a infinitely recursive type.

Example: https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=671872049ef51f20f8bcc976177c6b62

if you comment the line `use tempfile;` the code will compile as expected.

edit: Made the MRE smaller.
