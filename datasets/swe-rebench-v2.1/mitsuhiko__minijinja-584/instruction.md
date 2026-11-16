Values comparison fails after 2.3.0
### Discussed in https://github.com/mitsuhiko/minijinja/discussions/582

<div type='discussions-op-text'>

<sup>Originally posted by **pando85** September 17, 2024</sup>
Hello,

I'm using minijinja since 2.0.0 and it is wonderful. But in the last update my program tests where broken because something like this:
```
    #[test]
    fn test_minijinja() {
        let vars = context! {};
        let new_vars = context! {..vars.clone()};
        assert_eq!(vars, new_vars);
    }
```
Anyone could guide me about why in minijinja 2.2.0 this worked and now I get an error? Is this an intended behavior? Any workarounds?

Thanks!
</div>
