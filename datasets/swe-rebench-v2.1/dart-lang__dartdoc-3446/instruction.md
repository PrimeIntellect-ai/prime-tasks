Libraries ranked higher than classes in search results
Some users found it surprising that a library is ranked higher than classes of the same name. Here's an example:

<img width="580" alt="image" src="https://github.com/dart-lang/dartdoc/assets/348942/5903ebe9-c21e-4bf0-940f-5582435981b4">

It makes sense that developers are more likely to be looking up classes and methods than libraries. @srawlins pointed out it's done at https://github.com/dart-lang/dartdoc/blob/main/lib/src/search.dart#L176. Maybe we can revisit this heuristic.

### Additional contract requirements

- For matching search results, a class ranks ahead of a same-name library.
- For matching search results, a method ranks ahead of a same-name library.
- Changing the relative ranking of libraries and members preserves the existing precedence of higher-ranked over lower-ranked packages among results of the same kind.
