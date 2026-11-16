Improve `no-dupe-disjunctions` by reordering alternatives
To implement `sort-alternatives`, I had to implement a method to decide whether two alternatives can be reordered.

We can use this method to improve the reporting of `no-dupe-disjunctions`. Right now, superset alternatives are not reported by default (e.g. `/\b(?:Foo|\w+)\b/`). But if the alternatives can be reordered, a superset alternative can be become a subset alternative (e.g. `/\b(?:Foo|\w+)\b/` == `/\b(?:\w+|Foo)\b/`).
