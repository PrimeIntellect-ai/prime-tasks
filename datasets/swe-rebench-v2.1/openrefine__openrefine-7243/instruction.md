Custom clustering function with non-GREL expressions
<!-- Describe the bug - Please add a clear and concise description of the bug above this line. You can delete this line if you want. It will be hidden in the final bug report -->

### To Reproduce

Steps to reproduce the behavior:

1. Register a custom clustering function with either a Jython `return 1` or Clojure `(float 1)` expression.
2. Then try to use the custom clustering function.

### Current Results

For Clojure:

```log
com.google.refine.expr.ParsingException: Parsing error at offset 7: Missing )
        at com.google.refine.grel.Parser.makeException(Parser.java:93)
        at com.google.refine.grel.Parser.parseFactor(Parser.java:250)
        at com.google.refine.grel.Parser.parseTerm(Parser.java:146)
        at com.google.refine.grel.Parser.parseSubExpression(Parser.java:124)
        at com.google.refine.grel.Parser.parseExpression(Parser.java:100)
        at com.google.refine.grel.Parser.<init>(Parser.java:79)
        at com.google.refine.grel.Parser.<init>(Parser.java:72)
        at com.google.refine.grel.Parser$1.parse(Parser.java:62)
        at com.google.refine.expr.MetaParser.parse(MetaParser.java:117)
        at com.google.refine.clustering.binning.UserDefinedKeyer.<init>(UserDefinedKeyer.java:48)
        ...
```

For Jython:

```log
java.lang.IllegalArgumentException: The object is null
        at com.google.refine.clustering.knn.UserDefinedDistance.convertToDouble(UserDefinedDistance.java:76)
        at com.google.refine.clustering.knn.UserDefinedDistance.compute(UserDefinedDistance.java:71)
        at com.google.refine.clustering.knn.kNNClusterer$BlockingClusteringRowVisitor$DistanceWrapper.d(kNNClusterer.java:192)
        at edu.mit.simile.vicino.clustering.NGramClusterer$BlockEvaluator.call(NGramClusterer.java:78)
        at edu.mit.simile.vicino.clustering.NGramClusterer$BlockEvaluator.call(NGramClusterer.java:51)
        ...
```

### Expected Behavior

Being able to use non-GREL expressions with custom clustering functions.

### Versions
 - Operating System: Windows 10
 - Browser Version: Firefox 136
 - JRE or JDK Version: embedded
 - OpenRefine: 3.9.2

### Additional context

[HIDDEN]

### Additional contract requirements

- For the Jython expression `return columnName`, evaluation must produce an `EvalError` whose string contains `columnName`. Parsing or evaluating the Clojure expression `(count columnName)` must throw a `ParsingException`.
- Custom clustering keyers and distances must parse and evaluate expressions in a supported non-GREL language when that language is specified in the expression, while continuing to support GREL expressions.
