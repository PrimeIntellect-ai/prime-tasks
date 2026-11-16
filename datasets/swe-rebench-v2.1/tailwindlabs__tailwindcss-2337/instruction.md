Dark mode `class` strategy not compatible with complex variants like `group-hover`
Using the dark mode stuff in `class` mode with `group-hover` enabled generates selectors like this:

```
.dark .dark\:group:hover .dark .dark\:group-hover\:bg-white
```

...which seems pretty wrong.

I think the correct output should be this:

```
.dark .group:hover .dark\:group-hover\:bg-white
```
