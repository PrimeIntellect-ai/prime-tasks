Changes in Queue.
#### Description of the problem
Queue module needs some refactoring.

- Queue methods are generally `enqueue()` and `dequeue()`
- front and rear pointers need to be properties because of their frequent change.
- `type(x) is not self._dtype` can be converted to `_check_type(type(x),self._dtype)`

This issue was briefly discussed in https://github.com/codezonediitj/pydatastructs/pull/139#issuecomment-598817536

Further suggestions are welcome.

I will be taking on this issue, since I'm also working on LinkedListStack side by side.

### Additional contract requirements

`Queue` and `Stack` are exported from `pydatastructs.miscellaneous_data_structures`.

Queue:
- `Queue(implementation='array', items=None)` constructs a queue. `implementation` accepts `'array'` (the default) and `'linked_list'`; `'linked_list'` selects the linked-list implementation. `items` is an optional list or tuple of initial elements.
- `Queue.append(x)` adds `x` to the rear of the queue.
- `Queue.popleft()` removes and returns the front element. For the linked-list implementation the returned value is a node whose `.data` attribute holds the element. It raises `IndexError` when the queue is empty.
- For the linked-list implementation, `front` and `rear` are properties returning the front and rear nodes respectively, or `None` when the queue is empty.
- For the linked-list implementation, `size` is a property returning the number of elements.
- `len(queue)` returns the number of elements.

Stack:
- `Stack(implementation='array', items=None)` constructs a stack. `implementation` accepts `'array'` (the default) and `'linked_list'`; `'linked_list'` selects the linked-list implementation. `items` is an optional list or tuple of initial elements.
- `Stack.push(x)` adds `x` on top of the stack.
- `Stack.pop()` removes and returns the top element. For the linked-list implementation the returned value is a node whose `.data` attribute holds the element. It raises `IndexError` when the stack is empty.
- `Stack.peek` is a property returning the top value without removing it.
- `Stack.is_empty` is a property that is `True` when the stack has no elements.
- For the linked-list implementation, `top` is a property returning the top node, or `None` when the stack is empty.
- For the linked-list implementation, `size` is a property returning the number of elements.
- `len(stack)` returns the number of elements.
- Constructing a stack with an unsupported `implementation` value raises `NotImplementedError`.


- For either linked-list implementation, passing a set as `items` raises `TypeError`. `str(queue)` must return `'[0, 1, 2, 3]'` for a queue containing `0`, `1`, `2`, and `3` in that order. `str(stack)` must return `'[1, 2, 3]'` for an array stack initialized with `[1, 2, 3]`, and `'[3, 2, 1]'` for a linked-list stack pushed in the order `1`, `2`, `3` or initialized with `[1, 2, 3]`.
