Iterate over NewType Vec<T>
Can I use a NewType wrapper around `Vec<T>` in `for x in y` template file?

If I use something like `struct X {values: Vec<Y>}` then I can easily get its data using `for x in values`. This template will compile to `for (_loop_index, x) in (&self.values).iter_into().enumerate()`.

But I want to use NewType instead of a normal struct.

So I need to iterate over `self.0` -> how do I write template for that?

`for x in self.0` returns `or (_loop_index, x) in (&self.self.0).into_iter().enumerate()`

`for x in 0` returns `for (_loop_index, x) in (&0).into_iter().enumerate()`

Is there something obvious that I am missing?

This is the struct I am playing with and the template in question:

```rust
#[derive(Template)]
#[template(path = "handlers.html", print="all")]
struct VA ( Vec<A>);

impl std::ops::DerefMut for VA {
    fn deref_mut(&mut self) -> &mut Vec<A>{
        &mut self.0
    }
}
```

```jinja2
{% for a in ??? %}
...
{% endfor %}
