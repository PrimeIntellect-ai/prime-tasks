LimitedHistory [HIDDEN].
[LimitedHistory](https://github.com/Axelrod-Python/Axelrod/blob/dev/axelrod/history.py#L107) inherits extend from [base class](https://github.com/Axelrod-Python/Axelrod/blob/dev/axelrod/history.py#L50).  However expected behavior is that LimitedHistory only keeps the last `memory_depth` history.

Should make this unittest on TestLimitedHistory pass.
```
    def test_extend(self):
        h1 = LimitedHistory(3, plays=[C, C, D], coplays=[C, C, C])
        self.assertEqual(list(h1), [C, C, D])
        h1.extend([C, C], [D, D])
        self.assertEqual(list(h1), [D, C, C])
```

### Additional contract requirements

- After an extension, `LimitedHistory` retains at most the most recent `memory_depth` entries in both its play and corresponding coplay histories, discarding older entries.
