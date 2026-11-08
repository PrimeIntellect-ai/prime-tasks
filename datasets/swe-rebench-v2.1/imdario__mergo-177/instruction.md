panic: reflect: reflect.Value.Set using unaddressable value merging nested structures
Hi,

I want to do a deep merge where non-empty dst attributes are overwritten with non-empty src attributes values but slices are appended, is this possible?

Can someone help me understand why this does't work?
```
package main

import (
        "fmt"

        "github.com/imdario/mergo"
)

type My struct {
        Name  string
        Data  []int
        Other map[string]Other
}

type Other struct {
        Foo string
        Bar int
        Baz []string
        Faz map[string]string
}

func main() {
        dst := My{
                Data: []int{1, 2, 3},
                Name: "Dest",
                Other: map[string]Other{
                        "stuff": Other{
                                Foo: "bar",
                                Bar: 0,
                        },
                },
        }

        new := My{
                Data: []int{4, 5},
                Name: "Source",
                Other: map[string]Other{
                        "stuff": Other{
                                Foo: "bar",
                                Bar: 1,
                        },
                        "Morestuff": Other{
                                Foo: "foo",
                                Bar: 2,
                        },
                },
        }

        new2 := My{
                Name: "Source2",
                Other: map[string]Other{
                        "stuff": Other{
                                Foo: "bar",
                                Bar: 1,
                        },
                        "Morestuff": Other{
                                Foo: "foo",
                                Bar: 2,
                                Baz: []string{"something", "wrong"},
                                Faz: map[string]string{
                                        "some": "some2",
                                },
                        },
                },
        }

        fmt.Println(dst)
        fmt.Println(new)
        fmt.Println(new2)
        mergo.Merge(&dst, &new, mergo.WithAppendSlice, mergo.WithOverride)
        fmt.Println(dst)
        mergo.Merge(&dst, &new2, mergo.WithAppendSlice, mergo.WithOverride)
        fmt.Println(dst)
}
```

I get:
```
$ go run test.go
{Dest [1 2 3] map[stuff:{bar 0 [] map[]}]}
{Source [4 5] map[Morestuff:{foo 2 [] map[]} stuff:{bar 1 [] map[]}]}
{Source2 [] map[stuff:{bar 1 [] map[]} Morestuff:{foo 2 [something wrong] map[some:some2]}]}
{Source [1 2 3 4 5] map[Morestuff:{foo 2 [] map[]} stuff:{bar 1 [] map[]}]}
panic: reflect: reflect.Value.Set using unaddressable value

goroutine 1 [running]:
reflect.flag.mustBeAssignable(0x95)
        /usr/local/Cellar/go/1.11.1/libexec/src/reflect/value.go:234 +0x157
reflect.Value.Set(0x10b0760, 0xc000022470, 0x95, 0x10b0760, 0xc000074480, 0x15)
        /usr/local/Cellar/go/1.11.1/libexec/src/reflect/value.go:1397 +0x2f
github.com/imdario/mergo.deepMerge(0x10b0760, 0xc000022470, 0x95, 0x10b0760, 0xc000022430, 0x95, 0xc000095b08, 0x3, 0xc00000a1c0, 0x0, ...)
        /Users/ldavim/go/src/github.com/imdario/mergo/merge.go:83 +0x1388
github.com/imdario/mergo.deepMerge(0x10bcde0, 0xc000022440, 0x99, 0x10bcde0, 0xc000022400, 0x99, 0xc000095b08, 0x2, 0xc00000a1c0, 0x0, ...)
        /Users/ldavim/go/src/github.com/imdario/mergo/merge.go:72 +0x23a7
github.com/imdario/mergo.deepMerge(0x10b0700, 0xc0000741a8, 0x195, 0x10b0700, 0xc000074268, 0x195, 0xc000095b08, 0x1, 0xc00000a1c0, 0x0, ...)
        /Users/ldavim/go/src/github.com/imdario/mergo/merge.go:115 +0x986
github.com/imdario/mergo.deepMerge(0x10b9ba0, 0xc000074180, 0x199, 0x10b9ba0, 0xc000074240, 0x199, 0xc000095b08, 0x0, 0xc00000a1c0, 0x199, ...)
        /Users/ldavim/go/src/github.com/imdario/mergo/merge.go:72 +0x23a7
github.com/imdario/mergo.merge(0x10a4780, 0xc000074180, 0x10a4780, 0xc000074240, 0xc000095ce8, 0x2, 0x2, 0x0, 0x0)
        /Users/ldavim/go/src/github.com/imdario/mergo/merge.go:251 +0x29f
github.com/imdario/mergo.Merge(0x10a4780, 0xc000074180, 0x10a4780, 0xc000074240, 0xc000095ce8, 0x2, 0x2, 0x0, 0x0)
        /Users/ldavim/go/src/github.com/imdario/mergo/merge.go:206 +0x71
main.main()
        /Users/ldavim/Desktop/test.go:72 +0xa28
exit status 2
```

So, the first merge works but the second one fails.

Thanks
