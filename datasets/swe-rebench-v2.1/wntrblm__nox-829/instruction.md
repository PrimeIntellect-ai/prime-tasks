Wrong starting directory when noxfile.py is a symlink
I have a project where I want the noxfille to be a symlink to a different shared file.  When I do this, it throws off the paths b/c nox follows the symlink and starts in that directory instead of starting in the directory where the symlink is.

```
 ❯ ls -l noxfile.py
lrwxrwxrwx 1 rsyring rsyring 21 May 15 23:09 noxfile.py -> ./template/noxfile.py

 ❯ nox -s cwd
nox > Running session cwd
nox > Creating virtual environment (uv) using python3 in .nox/cwd
cwd is: /home/rsyring/projects/copier-py-package/template
```

Was this an intentional design decision?  If not, how about starting where the symlink is instead (i.e. don't follow it)?

Thanks for your work on this project and consideration.
