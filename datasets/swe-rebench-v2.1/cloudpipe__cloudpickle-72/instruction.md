Python 3.6 compatibility issue
A first quick testing with dask shows the bytecode analysis in cloudpickle isn't 3.6-compatible:
```
    @staticmethod
    def extract_code_globals(co):
        """
            Find all globals names read or written to by codeblock co
            """

        code = getattr(co, 'co_code', None)
        if code is None:
            return set()
        if not PY3:
            code = [ord(c) for c in code]
        names = co.co_names
        out_names = set()

        n = len(code)
        i = 0
        extended_arg = 0
        while i < n:
            op = code[i]

            i += 1
            if op >= HAVE_ARGUMENT:
                oparg = code[i] + code[i+1] * 256 + extended_arg
                extended_arg = 0
                i += 2
                if op == EXTENDED_ARG:
                    extended_arg = oparg*65536
                if op in GLOBAL_OPS:
>                   out_names.add(names[oparg])
E                   IndexError: tuple index out of range
```
