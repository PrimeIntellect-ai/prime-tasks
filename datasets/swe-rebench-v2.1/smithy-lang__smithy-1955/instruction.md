NumberNode's equal definition is impacted by the underlying representation
I'm not sure whether this qualifies as a bug, as it's directly coming from what I'd qualify as a java gotcha, but the two nodes values defined below are not equal with one another :

* `Node.from(new java.math.BigDecimal("1.0e+10"))`
* `Node.from(1.0e+10)`

This makes comparing some models hard. It'd be nice to have the `equals` method of number nodes protect against this gotcha.
