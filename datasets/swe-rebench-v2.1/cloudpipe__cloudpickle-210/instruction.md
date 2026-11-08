Pickling Annotations can _still_ fail
I'm getting some strange behaviour related to #193. Sorry to open the typing can of worms.

I'm using Python 3.7 and `cloudpickle==0.5.6` but have been using cloudpickle via `distributed==1.23.2`. Which I reported over at: https://github.com/dask/distributed/issues/2291

The above code sample works for me. However, the following does not:

```python
from typing import Optional
from distributed import Client

def f2() -> Optional[int]:
    return 1

def f1() -> int:
    return 1

def main():
    client = Client()
    print(client.submit(f1).result())  # works. prints 1
    print(client.submit(f2).result())  # fail. raises
    client.close()

if __name__ == '__main__':
    main()
```

Apologies that this includes a dask dependency. I tried to reproduce with the above code snippet but I don't get an exception:

```python
from typing import Optional
import cloudpickle

cloudpickle.dumps(Optional[int], protocol=cloudpickle.DEFAULT_PROTOCOL)
```

I'm a little bemused to where the problem is coming from now with those results.
