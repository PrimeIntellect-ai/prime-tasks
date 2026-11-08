Trait in a trait impl not automatically considered in-scope
![screenshot-2021-05-21-19:03:48](https://user-images.githubusercontent.com/1786438/119173285-5a0aff00-ba67-11eb-8752-6595243907ae.png)

Here, the method call to `fmt` is unresolved, but it should resolve to `<Subtree as Display>::fmt`. The implemented trait is normally considered to be in scope while in the impl block, maybe that logic is missing from rust-analyzer?
