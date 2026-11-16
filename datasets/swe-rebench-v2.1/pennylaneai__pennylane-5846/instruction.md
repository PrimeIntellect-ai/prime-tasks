[BUG] QAOA layers incorrectly forbid `Sum` observables
### Expected behavior

A `Sum` observable should be treated just like a legacy hamiltonian object or a new `LinearCombination` object.

### Actual behavior

The `QAOA` layers manually raise an error during a validation step, forbidding `Sum` and other multi-term op math objects other than the legacy Hamiltonian and `LinearCombination`.

### Additional information

_No response_

### Source code

```shell
#imports
import pennylane as qml
from pennylane import numpy as np

from pennylane import qaoa

import cmath
import matplotlib.pyplot as plt

# cost and mixer hamiltonians
cost_H = qml.PauliZ(0) + qml.PauliZ(1) + qml.PauliZ(2)

mixer_H = qml.PauliX(0) + qml.PauliX(1) + qml.PauliX(2)

# layers, qnode
wires = [0,1,2]
num_layers = 5

def qaoa_layer(gamma, alpha):
    qaoa.cost_layer(gamma, cost_H)
    qaoa.mixer_layer(alpha, mixer_H)

def circuit(params):
    for w in wires:
        qml.Hadamard(w)
    qml.layer(qaoa_layer, num_layers, params[0], params[1])

dev = qml.device("default.qubit", wires=wires)

@qml.qnode(dev)
def cost_function(params):
    circuit(params)
    return qml.expval(cost_H)

params = np.array([[0.5]*num_layers, [0.5]*num_layers], requires_grad = True)

cost_function(params)
```


### Tracebacks

```shell
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
Cell In[38], line 41
     38 params = np.array([[0.5]*num_layers, [0.5]*num_layers], requires_grad = True)
     40 for _ in range(steps):
---> 41     params = opt.step(cost_function, params)

File ~\anaconda3\Lib\site-packages\pennylane\optimize\gradient_descent.py:93, in GradientDescentOptimizer.step(self, objective_fn, grad_fn, *args, **kwargs)
     75 def step(self, objective_fn, *args, grad_fn=None, **kwargs):
     76     """Update trainable arguments with one step of the optimizer.
     77
     78     Args:
   (...)
     90         If single arg is provided, list [array] is replaced by array.
     91     """
---> 93     g, _ = self.compute_grad(objective_fn, args, kwargs, grad_fn=grad_fn)
     94     new_args = self.apply_grad(g, args)
     96     # unwrap from list if one argument, cleaner return

File ~\anaconda3\Lib\site-packages\pennylane\optimize\gradient_descent.py:122, in GradientDescentOptimizer.compute_grad(objective_fn, args, kwargs, grad_fn)
    104 r"""Compute gradient of the objective function at the given point and return it along with
    105 the objective function forward pass (if available).
    106
   (...)
    119     will not be evaluted and instead ``None`` will be returned.
    120 """
    121 g = get_gradient(objective_fn) if grad_fn is None else grad_fn
--> 122 grad = g(*args, **kwargs)
    123 forward = getattr(g, "forward", None)
    125 num_trainable_args = sum(getattr(arg, "requires_grad", False) for arg in args)

File ~\anaconda3\Lib\site-packages\pennylane\_grad.py:165, in grad.__call__(self, *args, **kwargs)
    162     self._forward = self._fun(*args, **kwargs)
    163     return ()
--> 165 grad_value, ans = grad_fn(*args, **kwargs)  # pylint: disable=not-callable
    166 self._forward = ans
    168 return grad_value

File ~\anaconda3\Lib\site-packages\autograd\wrap_util.py:20, in unary_to_nary.<locals>.nary_operator.<locals>.nary_f(*args, **kwargs)
     18 else:
     19     x = tuple(args[i] for i in argnum)
---> 20 return unary_operator(unary_f, x, *nary_op_args, **nary_op_kwargs)

File ~\anaconda3\Lib\site-packages\pennylane\_grad.py:183, in grad._grad_with_forward(fun, x)
    177 @staticmethod
    178 @unary_to_nary
    179 def _grad_with_forward(fun, x):
    180     """This function is a replica of ``autograd.grad``, with the only
    181     difference being that it returns both the gradient *and* the forward pass
    182     value."""
--> 183     vjp, ans = _make_vjp(fun, x)  # pylint: disable=redefined-outer-name
    185     if vspace(ans).size != 1:
    186         raise TypeError(
    187             "Grad only applies to real scalar-output functions. "
    188             "Try jacobian, elementwise_grad or holomorphic_grad."
    189         )

File ~\anaconda3\Lib\site-packages\autograd\core.py:10, in make_vjp(fun, x)
      8 def make_vjp(fun, x):
      9     start_node = VJPNode.new_root()
---> 10     end_value, end_node =  trace(start_node, fun, x)
     11     if end_node is None:
     12         def vjp(g): return vspace(x).zeros()

File ~\anaconda3\Lib\site-packages\autograd\tracer.py:10, in trace(start_node, fun, x)
      8 with trace_stack.new_trace() as t:
      9     start_box = new_box(x, t, start_node)
---> 10     end_box = fun(start_box)
     11     if isbox(end_box) and end_box._trace == start_box._trace:
     12         return end_box._value, end_box._node

File ~\anaconda3\Lib\site-packages\autograd\wrap_util.py:15, in unary_to_nary.<locals>.nary_operator.<locals>.nary_f.<locals>.unary_f(x)
     13 else:
     14     subargs = subvals(args, zip(argnum, x))
---> 15 return fun(*subargs, **kwargs)

File ~\anaconda3\Lib\site-packages\pennylane\workflow\qnode.py:1092, in QNode.__call__(self, *args, **kwargs)
   1089     override_shots = kwargs["shots"]
   1091 # construct the tape
-> 1092 self.construct(args, kwargs)
   1094 original_grad_fn = [self.gradient_fn, self.gradient_kwargs, self.device]
   1095 self._update_gradient_fn(shots=override_shots, tape=self._tape)

File ~\anaconda3\Lib\site-packages\pennylane\workflow\qnode.py:929, in QNode.construct(self, args, kwargs)
    926     self.interface = qml.math.get_interface(*args, *list(kwargs.values()))
    928 with qml.queuing.AnnotatedQueue() as q:
--> 929     self._qfunc_output = self.func(*args, **kwargs)
    931 self._tape = QuantumScript.from_queue(q, shots)
    933 params = self.tape.get_parameters(trainable_only=False)

Cell In[38], line 32, in cost_function(params)
     30 @qml.qnode(dev)
     31 def cost_function(params):
---> 32     circuit(params)
     33     return qml.expval(cost_H)

Cell In[38], line 26, in circuit(params)
     24 for w in wires:
     25     qml.Hadamard(w)
---> 26 qml.layer(qaoa_layer, num_layers, params[0], params[1])

File ~\anaconda3\Lib\site-packages\pennylane\templates\layer.py:213, in layer(template, depth, *args, **kwargs)
    211 for i in range(0, int(depth)):
    212     arg_params = [k[i] for k in args]
--> 213     template(*arg_params, **kwargs)

Cell In[38], line 20, in qaoa_layer(gamma, alpha)
     19 def qaoa_layer(gamma, alpha):
---> 20     qaoa.cost_layer(gamma, cost_H)
     21     qaoa.mixer_layer(alpha, mixer_H)

File ~\anaconda3\Lib\site-packages\pennylane\qaoa\layers.py:103, in cost_layer(gamma, hamiltonian)
     49 r"""Applies the QAOA cost layer corresponding to a cost Hamiltonian.
     50
     51 For the cost Hamiltonian :math:`H_C`, this is defined as the following unitary:
   (...)
    100
    101 """
    102 [HIDDEN]
--> 103     raise ValueError(
    104         f"hamiltonian must be of type pennylane.Hamiltonian, got {type(hamiltonian).__name__}"
    105     )
    107 if not _diagonal_terms(hamiltonian):
    108     raise ValueError("hamiltonian must be written only in terms of PauliZ and Identity gates")

ValueError: hamiltonian must be of type pennylane.Hamiltonian, got Sum
```


### System information

```shell
master
```


### Existing GitHub issues

- [X] I have searched existing GitHub issues to make sure the issue does not already exist.

### Additional contract requirements

Both `qaoa.cost_layer` and `qaoa.mixer_layer` must apply their corresponding evolution when given a valid `Sum` observable, rather than rejecting it merely for being a `Sum`. A cost-layer `Sum` with terms outside the existing Pauli-Z and Identity restriction must still be rejected.
