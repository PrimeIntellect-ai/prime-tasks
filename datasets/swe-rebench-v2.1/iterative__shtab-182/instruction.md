Tabs after redirecting stdout do not complete files in bash
When working in shells it is quite common that a command outputs something to stdout an the user wants to redirect this to a file, for example:
```bash
ls > /tmp/list_of_files.txt
```
Using tab completion after the `>` redirection is very useful to navigate existing directories or complete files. This works out of the box for commands that don't have any tab completion, since anyway this no longer depends on the command.

Unfortunately, when an shtab completion script is activated, the completion after redirection no longer works. For instance take the following script:
```python
from argparse import ArgumentParser
import shtab

parser = ArgumentParser()
parser.add_argument("--number", type=float)
shtab.add_argument_to(parser, "--shell-completion")
print(parser.parse_args())
```

The following are cases that work and don't work:
```bash
$ cli.py --n<TAB>
$ cli.py --number

$ cli.py > <TAB><TAB>
[BUG: does not complete anything]

$ cli.py >> <TAB><TAB>
[BUG: does not complete anything]

$ cli.py 2> <TAB><TAB>
[BUG: does not complete anything]

$ cli.py --number 1 &> <TAB><TAB>
[OK: completes files]

$ cli.py --number 1 2>&1 <TAB><TAB>
[OK: completes files]

$ cli.py --number 1 | <TAB><TAB>
[OK: completes commands]
```

### Additional contract requirements

- `shtab.complete(parser, shell="bash")` returns a `str` containing the generated shell-completion script for the given parser and shell.


- For a Bash completion script generated from a parser with `prog="test"`, it must define and allow invocation of the function `_shtab_test`. Bash completion must offer filesystem path completions after `2>>` as well.
