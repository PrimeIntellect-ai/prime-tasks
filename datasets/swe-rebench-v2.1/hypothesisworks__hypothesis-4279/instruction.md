Shrink NaN to canonical form
```
for s in [0, 2, 4]:
    @given(st.lists(st.integers()|st.floats()))
    @seed(s)
    def sort_is_reversible(l):
        assert sorted(l, reverse=True) == list(reversed(sorted(l)))
    try:
        sort_is_reversible()
    except AssertionError as e:
        print(e.__notes__[0].replace("\n", ""))
```
→
```
Falsifying example: sort_is_reversible(l=[0, -nan],)
Falsifying example: sort_is_reversible(l=[0, nan],)
Falsifying example: sort_is_reversible(l=[0, struct.unpack('d', struct.pack('Q', 0xfff8000000000001))[0]],)
```

### Additional contract requirements

All NaN values, regardless of sign or payload bits, must shrink to the same canonical NaN representation.
