Wildcard modifier `lower` matches digits
### What happened, and what did you expect to happen?

running the following code
```elvish
touch 3 4 5 a b C
echo *[digit] # expected output : 3 4 5
echo *[letter] # expected output : a b C
echo *[lower] # expected output : a b
```
results in
```
3 4 5
C a b
3 4 5
```

so the wildcard modifier `lower` is actually matching digits instead of lowercase letters.

### Output of "elvish -version"

0.21.0+archlinux1

### Code of Conduct

- [X] I agree to follow Elvish's [Code of Conduct](https://src.elv.sh/CODE_OF_CONDUCT.md).
