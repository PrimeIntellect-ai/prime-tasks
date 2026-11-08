BUG: Running pytask.build twice in one python call gives `ValueError: list.remove(x): x not in list`
- [x] I have checked that this issue has not already been reported.
- [x] I have confirmed this bug exists on the latest version of pytask.
- [ ] (optional) I have confirmed this bug exists on the `main` branch of pytask.

---

#### Code Sample, a copy-pastable example

```python
import pathlib
from typing import Annotated

import numpy as np
import pandas as pd
import pytask

@pytask.task(name="task1")
def task1(path: Annotated[pathlib.Path, pytask.Product] = pathlib.Path(".") / "data.pkl") -> None:
    # The example code from the webpage
    rng = np.random.default_rng(0)
    beta = 2

    x = rng.normal(loc=5, scale=10, size=1_000)
    epsilon = rng.standard_normal(1_000)

    y = beta * x + epsilon

    df = pd.DataFrame({"x": x, "y": y})
    df.to_pickle(path)

def main():
    session1 = pytask.build(
        tasks=[task1]
    )

    session2 = pytask.build(
        tasks=[task1]
    )

if __name__ == "__main__":
    main()
```

#### Problem description

Please find a minimal example above. The program produces a ValueError in the second call (cf. console log below). Also the formatting is broken. The last line of the first run is overwritten. And the summary box is missing. The second execution seems broken.

Console log:
```
(bestofbothworlds) > $ python demo2.py
─────────────────────────────────────────────────────────────── Start pytask session ───────────────────────────────────────────────────────────────
Platform: linux -- Python 3.11.9, pytask 0.5.0, pluggy 1.5.0
Root: /home/max/git.intellisec.de/mnoppel/minimalexample
Collected 1 task.

╭─────────────────┬─────────╮
│ Task            │ Outcome │
├─────────────────┼─────────┤
│ demo2.py::task1 │ .       │
╰─────────────────┴─────────╯

────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
╭─────────── Summary ───────────╮
│  1  Collected task            │
│  1  Succeeded       (100.0%)  │
ValueError: list.remove(x): x not in list
╭─────────────────┬─────────╮
│ Task            │ Outcome │
├─────────────────┼─────────┤
│ demo2.py::task1 │ .       │
╰─────────────────┴─────────╯
               Completed: 1/1%
```

#### Expected Output

I expected the program just to do the same thing again but recognizing the already existing file. So it would print something like:

1. 1 Job found. Executing.
2. Artifact present. Nothing to do.


**Some background on why I want to use this pattern.**
The problem originated because I want to combine Hydra https://hydra.cc/ together with pytask. Using Hydra for the configuration and job handling (I need slurm jobs) and pytask to keep track of what has to be done in the individual runs. Here I have a attached the above example (`demo2.py`) and the example with hydra (`demo1.py`). You can call the Hydra example with `python main.py -m method=A,B`. https://cloud.noppelmax.online/s/GftbJbHWpXegy8w



Thanks for your service for the community and the great tool!

Max
