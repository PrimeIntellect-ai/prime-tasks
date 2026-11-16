Bar length not calculated correctly when ANSI color codes are used
I am using ANSI color codes in the progress bar description string to emphasize success, failure etc.

Unfortunately, the bar length calculation doesn't work as expected with these color codes.

In the example below, the bar stops short of the terminal width by 13 characters, which is the combined length of the ANSI control sequences.

```python
from tqdm import tqdm

ansi = {'BOLD': '\033[1m',
        'RED': '\033[91m',
        'END': '\033[0m'}

text = '{BOLD}{RED}Failed{END}: ...'.format(**ansi)

pbar = tqdm(total=100, desc=text)
pbar.close()
```

Output (example):
```
Failed: ...:   0%|                                  | 0/100 [00:00<?, ?it/s]
```
Expected:
```
Failed: ...:   0%|                                               | 0/100 [00:00<?, ?it/s]
```

[HIDDEN]

[HIDDEN]

I'd be happy to submit a PR, but I don't know if this is a desired feature. Performance should not be an issue, as the stripping executes in < 1 µs.

---

```
 >>> print(tqdm.__version__)
4.24.0
>>> print(sys.version)
3.7.0 (default, Jun 28 2018, 07:39:16)
[Clang 4.0.1 (tags/RELEASE_401/final)]
>>> print(sys.platform)
darwin
```

### Additional contract requirements

- When a progress-bar description contains ANSI escape sequences, calculate the available bar space using the description’s visible width, so nonprinting sequences do not shorten the displayed bar.
