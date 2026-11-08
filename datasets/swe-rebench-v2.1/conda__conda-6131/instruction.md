ValidationError: invalid value for timestamp
MODERATOR EDIT:  This issue relates to an error that looks something like

    ValidationError: Invalid value 1505856869.685 for timestamp

The issue relates to using conda 4.3.28, and then downgrading (presumably via conda-forge) to a previous version of conda, like 4.3.27.

# SOLUTION #

### To fix on macOS:

    # in the command below, set PATH_TO_ENVIRONMENT yourself
[HIDDEN]

### To fix on Linux:

    # in the command below, set PATH_TO_ENVIRONMENT yourself
[HIDDEN]

### To fix on Windows:

Open notepad, and copy the contents below to `c:\fix_timestamps.py`

[HIDDEN]

----

EDITED: I realized this is not a pyqt issue, it's a conda issue

### steps to reproduce

1. Install 64-bit miniconda on windows 10 (version 4.3.27)
2. conda update to `4.3.28-py36h9daa44c_0`
3. conda install -c anaconda spyder
4. conda config --add channels conda-forge

Now any calls to conda results in the print-out below.

### conda info

This prints any time I try to use a conda command.

```conda install -c dsdale24 pyqt5
An unexpected error has occurred.
Please consider posting the following information to the
conda GitHub issue tracker at:

    https://github.com/conda/conda/issues



Current conda install:

               platform : win-64
          conda version : 4.3.27
       conda is private : False
      conda-env version : 4.3.27
    conda-build version : not installed
         python version : 3.6.2.final.0
       requests version : 2.18.4
       root environment : C:\Users\jrinker\Miniconda3  (writable)
    default environment : C:\Users\jrinker\Miniconda3
       envs directories : C:\Users\jrinker\Miniconda3\envs
                          C:\Users\jrinker\AppData\Local\conda\conda\envs
                          C:\Users\jrinker\.conda\envs
          package cache : C:\Users\jrinker\Miniconda3\pkgs
                          C:\Users\jrinker\AppData\Local\conda\conda\pkgs
           channel URLs : https://conda.anaconda.org/dsdale24/win-64
                          https://conda.anaconda.org/dsdale24/noarch
                          https://conda.anaconda.org/conda-forge/win-64
                          https://conda.anaconda.org/conda-forge/noarch
                          https://repo.continuum.io/pkgs/main/win-64
                          https://repo.continuum.io/pkgs/main/noarch
                          https://repo.continuum.io/pkgs/free/win-64
                          https://repo.continuum.io/pkgs/free/noarch
                          https://repo.continuum.io/pkgs/r/win-64
                          https://repo.continuum.io/pkgs/r/noarch
                          https://repo.continuum.io/pkgs/pro/win-64
                          https://repo.continuum.io/pkgs/pro/noarch
                          https://repo.continuum.io/pkgs/msys2/win-64
                          https://repo.continuum.io/pkgs/msys2/noarch
            config file : C:\Users\jrinker\.condarc
             netrc file : None
           offline mode : False
             user-agent : conda/4.3.27 requests/2.18.4 CPython/3.6.2 Windows/10 Windows/10.0.15063
          administrator : False

`$ C:\Users\jrinker\Miniconda3\Scripts\conda install -c dsdale24 pyqt5`




    Traceback (most recent call last):
      File "C:\Users\jrinker\Miniconda3\lib\site-packages\conda\exceptions.py", line 640, in conda_exception_handler
        return_value = func(*args, **kwargs)
      File "C:\Users\jrinker\Miniconda3\lib\site-packages\conda\cli\main.py", line 140, in _main
        exit_code = args.func(args, p)
      File "C:\Users\jrinker\Miniconda3\lib\site-packages\conda\cli\main_install.py", line 80, in execute
        install(args, parser, 'install')
      File "C:\Users\jrinker\Miniconda3\lib\site-packages\conda\cli\install.py", line 160, in install
        linked_dists = install_linked(prefix)
      File "C:\Users\jrinker\Miniconda3\lib\site-packages\conda\core\linked_data.py", line 123, in linked
        return set(linked_data(prefix, ignore_channels=ignore_channels).keys())
      File "C:\Users\jrinker\Miniconda3\lib\site-packages\conda\core\linked_data.py", line 115, in linked_data
        load_linked_data(prefix, dist_name, ignore_channels=ignore_channels)
      File "C:\Users\jrinker\Miniconda3\lib\site-packages\conda\core\linked_data.py", line 68, in load_linked_data
        linked_data_[prefix][dist] = rec = IndexRecord(**rec)
      File "C:\Users\jrinker\Miniconda3\lib\site-packages\conda\_vendor\auxlib\entity.py", line 702, in __call__
        instance = super(EntityType, cls).__call__(*args, **kwargs)
      File "C:\Users\jrinker\Miniconda3\lib\site-packages\conda\_vendor\auxlib\entity.py", line 719, in __init__
        setattr(self, key, kwargs[key])
      File "C:\Users\jrinker\Miniconda3\lib\site-packages\conda\_vendor\auxlib\entity.py", line 424, in __set__
        instance.__dict__[self.name] = self.validate(instance, self.box(instance, val))
      File "C:\Users\jrinker\Miniconda3\lib\site-packages\conda\_vendor\auxlib\entity.py", line 465, in validate
        raise ValidationError(getattr(self, 'name', 'undefined name'), val)
    conda._vendor.auxlib.exceptions.ValidationError: Invalid value 1505856869.685 for timestamp
```

### things I've tried

- Removing conda forge from channels
- `conda update conda` (still prints out error)

### Additional contract requirements

- Provide the public `IndexRecord` class in `conda.models.index_record`.
- Interpret timestamps below `253402300799` as seconds and convert them to milliseconds; leave timestamps at or above that threshold in milliseconds. Accept the reported timestamp `1505856869.685` and normalize it to `1505856869685` milliseconds since the Unix epoch.
- Expose the normalized timestamp as an integer in milliseconds since the Unix epoch.
- Return a plain dictionary from `dump()` with the timestamp expressed in milliseconds.
- Preserve additional accepted fields on the record and in the dictionary returned by `dump()`.
