Filter in child template replaces other filter in parent template
## Description

It's probably best to just see the reproduction. As far as I can tell, using `{% set foo = "value" | <filter> %}` in a template that extends another affects filters in the base template.

## Reproduction steps

Rust minimum working example with `minijinja = "=2.1.1"` in `Cargo.toml`:

```rust
fn main() {
    let mut env = minijinja::Environment::empty();

    env.add_filter("reverse", minijinja::filters::reverse);
    env.add_filter("nop", |value: String| value);

    const ONE: &str = r#"{{ "foobar" | nop }}"#;
    const TWO: &str = r#"{% extends "one.html" %}{% set foo = "" | reverse %}"#;

    env.add_template("one.html", ONE).unwrap();
    env.add_template("two.html", TWO).unwrap();

    let template = env.get_template("one.html").unwrap();
    println!("{}", template.render(minijinja::context! {}).unwrap());

    let template = env.get_template("two.html").unwrap();
    println!("{}", template.render(minijinja::context! {}).unwrap());
}
```

This prints "foobar" and "raboof" (!).

It does not matter where the set statement is, so this also produces the same result:

```rust
const TWO: &str = r#"{% set foo = "" | reverse %}{% extends "one.html" %}"#;
```

For completeness, Python/Jinja2 3.1.4 minimum working example:

```python
from jinja2 import Environment, DictLoader
loader = DictLoader({
    "one.html": '{{ "foobar" | nop }}',
    "two.html": '{% extends "one.html" %}{% set foo = "" | reverse %}',
})
env = Environment(loader=loader)
env.filters["nop"] = lambda v: v
print(env.get_template("one.html").render())
print(env.get_template("two.html").render())
```

Prints `foobar` and `foobar` as expected.

Additional helpful information:

- Version of minijinja: 2.1.1 (f4bf71af278c578cbcc91d0b1ff092910208bc86f7b3750364642bd424e3dcd3), 2.1.0, 2.0.0, 1.0.21, 0.30.0, 0.26.0
- Version of rustc: 1.80.0 (051478957 2024-07-21), 1.79.0 (129f3b996 2024-06-10), 1.76.0 (07dca489a 2024-02-04)
- Operating system and version: macOS Sonoma 14.5 (23F79)

As far as I can see, 0.25.0 works as expected, and 0.26.0 introduced this behaviour.

## What did you expect

I'd expect the example to print "foobar" in both cases, as the Python example and version 0.25.0 does.
