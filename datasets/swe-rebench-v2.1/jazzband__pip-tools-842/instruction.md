pip-tools --upgrade --dry-run --output-file requirements.pc should not erase requirements.pc when --dry-run is specified
Describe the issue briefly here.

##### Environment Versions

1. OS Type

$ uname -v
Darwin Kernel Version 16.7.0: Thu Dec 20 21:53:35 PST 2018; root:xnu-3789.73.31~1/RELEASE_X86_64

2. Python version: `$ python -V`

$ python -V
Python 3.7.3

3. pip version:  `$ pip --version`

$ pip --version
pip 19.0.3[snip]

4. pip-tools version: `$ pip-compile --version`

$ pip-compile --version
pip-compile, version 3.8.0

##### Steps to replicate

1. Run pip-compile --output-file requirements.pc requirements.in
2. Run pip-compile --upgrade --dry-run --output-file requirements.pc
3. requirements.pc is recreated as an empty file rather than no effects taking place via --dry-run

##### Expected result

requirements.pc should be left alone if --upgrade is used with --dry-run

##### Actual result

requirements.pc is replaced with an empty file

##### Commentary

I'd first like to say thank you to everyone for this wonderful tool. I appreciate the sheer amount of work and attention to detail. Apologies if this is a repeat issue; I did look to see if this was already reported.

I suspect this behavior is due to click's file handling behavior being left turned on even for --dry-run?

As for why I'm using this mode at all and why other people may not have seen this...

I'm trying to run the command to let our developers know what *would* be upgraded vs. the existing requirements.pc and my expectation is that I'd be able to use the --output-file - stdout function and pipe to diff vs. the existing requirements.pc file with no damage caused. BUT, because when run with --dry-run no output is created so stdout is empty. When attempting to use the existing file and perhaps run git diff to highlight differences, the file disappears (bad). Another option, and one I'll take for the time being, is to run the upgrade command without --run-run into a dummy file and diff that vs. the real one. Unless someone else has a better idea?

Thanks, again, and warm regards.

### Additional contract requirements

- With `--dry-run --upgrade --output-file requirements.txt`, stdout must include `small-fake-a==0.2`.
- With `--dry-run --output-file requirements.txt` and no upgrade option, when `requirements.txt` does not already exist, stdout must include `small-fake-a==0.2`. With `--dry-run --upgrade-package small-fake-a --output-file requirements.txt`, stdout must also include `small-fake-a==0.2`.
- When the output file already exists (whether given via `--output-file` or derived from the input file) and neither `--upgrade` nor `--upgrade-package` is given, the existing pinned version is retained: with an existing `requirements.txt` containing `small-fake-a==0.1`, `--dry-run` must print `small-fake-a==0.1` to stdout.
