call ellipsis by command style failed
### The following program `sample.gop` triggers an unexpected result

```coffee
// add a sample
func test(s ...string) {
}
a := ["1","2","3"]
test(a...)
test a... // smart format `test(a...)` =>` test a...`
```


### Expected result

```console
pass
```


### Got

```console
main.gop:5:11: expected ';', found 'EOF'
```


### Gop Version

main version

### Additional Notes

smart format `test(a...)` =>` test a...`
