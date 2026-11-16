Relationship field in tag/value parser rejects valid values
Thanks for making this Go library! Having the ability to use SPDX files in Go is excellent.

I think I've found a bug in how the tag/value parser handles Relationship fields: [SPDX 2.2 specifies](https://spdx.github.io/spdx-spec/7-relationships-between-SPDX-elements/) this example is valid:

```
Relationship: SPDXRef-BobBrowser CONTAINS NOASSERTION
```

However, with a file containing

```
Relationship: SPDXRef-ion-tester CONTAINS NOASSERTION
```

the `tvloader.Load2_2(r)` call returns an error stating `missing SPDXRef- prefix for element identifier`.

The same file successfully passes with the [Java validator](https://github.com/spdx/tools-java):

```
$ java -jar /tmp/tools-java-0.0.6-jar-with-dependencies.jar Verify ./spdx-test-1.spdx TAG

This SPDX Document is valid.
```

I've made a reproduction repository at https://github.com/matthewkmayer/spdx-go-repro . It can be cloned then run with `go run .` to see the error.

I tried to find tests for this scenario in this repo but didn't find any. Perhaps guidance on how to find the relevant tests could help us solve this. 👍
