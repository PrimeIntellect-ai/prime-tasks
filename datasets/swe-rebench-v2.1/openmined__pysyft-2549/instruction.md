URGENT: bug in encrypted autograd
**Describe the bug**
For some reason, calling loss.backward() on a pointer using normal autograd then breaks our ability to call loss.backward() on an encrypted loss variable even on two totally separate examples.

**To Reproduce**
```
import torch
import torch as th
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
import syft as sy

# Set everything up
hook = sy.TorchHook(torch)

big_hospital = sy.VirtualWorker(hook, id="big_hospital2")
small_hospital = sy.VirtualWorker(hook, id="small_hospital2")
crypto_provider = sy.VirtualWorker(hook, id="crypto_provider2")

# A Toy Model
class Net(nn.Module):
    def __init__(self):
        super(Net, self).__init__()
        self.fc1 = nn.Linear(2, 2)
        self.fc2 = nn.Linear(2, 1)

    def forward(self, x):
        x = self.fc1(x)
        x = F.relu(x)
        x = self.fc2(x)
        return x

def federated():
    # A Toy Dataset
    data = th.tensor([[0,0],[0,1],[1,0],[1,1.]])
    target = th.tensor([[0],[0],[1],[1.]])

    model = Net()

    # Training Logic
    opt = optim.SGD(params=model.parameters(),lr=0.1)

    data = data.send(big_hospital)
    target = target.send(big_hospital)

    # NEW) send model to correct worker
    model.send(data.location)

    # 1) erase previous gradients (if they exist)
    opt.zero_grad()

    # 2) make a prediction
    pred = model(data)

    # 3) calculate how much we missed
    loss = ((pred - target)**2).sum()

    # 4) figure out which weights caused us to miss
    loss.backward()

    print("Done!")

def encrypted():
    # A Toy Dataset
    data2 = th.tensor([[0,0],[0,1],[1,0],[1,1.]])
    target2 = th.tensor([[0],[0],[1],[1.]])

    model2 = Net()

    # We encode everything
    data2 = data2.fix_precision().share(big_hospital, small_hospital, crypto_provider=crypto_provider, requires_grad=True)
    target2 = target2.fix_precision().share(big_hospital, small_hospital, crypto_provider=crypto_provider, requires_grad=True)
    model2 = model2.fix_precision().share(big_hospital, small_hospital, crypto_provider=crypto_provider, requires_grad=True)

    opt2 = optim.SGD(params=model2.parameters(),lr=0.1).fix_precision()


    # 1) erase previous gradients (if they exist)
    opt2.zero_grad()

    # 2) make a prediction
    pred2 = model2(data2)

    # 3) calculate how much we missed
    loss2 = ((pred2 - target2)**2).sum()

    # 4) figure out which weights caused us to miss
    loss2.backward()

#     # 5) change those weights
#     opt2.step()

#     # 6) print our progress
#     print(loss2.get().float_precision())

    print("Done")

run_broken = True

# make sure to re-start your jupyter notebook / environment with each test.
if(run_broken):
    # Breaks
    federated()
    encrypted() # breaks here - something about loss2.backward() causes the federated() demo to break
else:
    # Works fine
    encrypted()
    federated()
```

Throws error:

```
---------------------------------------------------------------------------
AttributeError                            Traceback (most recent call last)
<ipython-input-1-db6dbbeffaa2> in <module>()
    100     # Breaks
    101     federated()
--> 102     encrypted() # breaks here - something about loss2.backward() causes the federated() demo to break
    103 else:
    104     # Works fine

<ipython-input-1-db6dbbeffaa2> in encrypted()
     84
     85     # 4) figure out which weights caused us to miss
---> 86     loss2.backward()
     87
     88 #     # 5) change those weights

/Users/atrask/anaconda/lib/python3.6/site-packages/syft-0.1.22a1-py3.6.egg/syft/frameworks/torch/hook/hook.py in overloaded_native_method(self, *args, **kwargs)
    683                 # Put back the wrappers where needed
    684                 response = syft.frameworks.torch.hook_args.hook_response(
--> 685                     method_name, response, wrap_type=type(self), new_self=self
    686                 )
    687

/Users/atrask/anaconda/lib/python3.6/site-packages/syft-0.1.22a1-py3.6.egg/syft/frameworks/torch/hook/hook_args.py in hook_response(attr, response, wrap_type, wrap_args, new_self)
    243         response_hook_function = hook_method_response_functions[attr_id]
    244         # Try running it
--> 245         new_response = response_hook_function(response)
    246
    247     except (IndexError, KeyError, AssertionError):  # Update the function in cas of an error

/Users/atrask/anaconda/lib/python3.6/site-packages/syft-0.1.22a1-py3.6.egg/syft/frameworks/torch/hook/hook_args.py in <lambda>(x)
    502         f = many_fold
    503
--> 504     return lambda x: f(lambdas, x)
    505
    506

/Users/atrask/anaconda/lib/python3.6/site-packages/syft-0.1.22a1-py3.6.egg/syft/frameworks/torch/hook/hook_args.py in two_fold(lambdas, args, **kwargs)
    520
    521 def two_fold(lambdas, args, **kwargs):
--> 522     return lambdas[0](args[0], **kwargs), lambdas[1](args[1], **kwargs)
    523
    524

/Users/atrask/anaconda/lib/python3.6/site-packages/syft-0.1.22a1-py3.6.egg/syft/frameworks/torch/hook/hook_args.py in <lambda>(i)
    480         if isinstance(r, (list, tuple))  # if the rule is a list or tuple.
    481         # Last if not, rule is probably == 1 so use type to return the right transformation.
--> 482         else lambda i: backward_func[wrap_type](i, **wrap_args)
    483         for a, r in zip(response, rules)  # And do this for all the responses / rules provided
    484     ]

/Users/atrask/anaconda/lib/python3.6/site-packages/syft-0.1.22a1-py3.6.egg/syft/frameworks/torch/hook/hook_args.py in <lambda>(i)
     73 backward_func = {
     74     TorchTensor: lambda i: i.wrap(),
---> 75     torch.Tensor: lambda i: i.wrap(),
     76     torch.nn.Parameter: lambda i: torch.nn.Parameter(data=i),
     77     PointerTensor: lambda i: i,

AttributeError: 'NoneType' object has no attribute 'wrap'
```

**Additional context**
latest version of PySyft from PyPI ('0.1.22a1')
