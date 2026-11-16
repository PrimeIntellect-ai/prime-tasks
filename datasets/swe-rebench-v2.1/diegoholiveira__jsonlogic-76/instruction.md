failing to check array items by index (from an empty array)
First of all, that's a great lib, thank you all for your hard work on this!

When we try to access an specific condition in an empty array, we get _index out of range_.
How can we check if the array is not empty before accessing their items?

[Quick playground example](https://go.dev/play/p/nxtgY9mj90L)

```go
logic := strings.NewReader(`{"if":[ false, {"var":"values.0.categories"}, "else" ]}`)
data := strings.NewReader(`{ "values": [] }`)

var result bytes.Buffer
if err := jsonlogic.Apply(logic, data, &result); err != nil {
    fmt.Printf("failed, %v", err)
}

fmt.Println(result.String())
```

In the example above, even forcing the _false_ in the `if` condition, it's still evaluating the _true_ part, causing the index out of range.
Shouldn't return the `"else"` value , even returning the error?
This is what the [JSON Logic playground](https://jsonlogic.com/play.html) returns:

![image](https://github.com/diegoholiveira/jsonlogic/assets/21963/6bac49af-48d8-4943-b718-7412f907fb6e)

Is there any other way to get the value of a property from an array's item (like `categories` from the first position in my example)?

Thank you
