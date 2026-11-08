Sorted Collections assertion
It would be great to have an assertion which can check if the Collection is already sorted. The assertion would also accept a `Comparator` instance to verify with. Similar (or same) as [AssertJ](http://javadox.com/org.assertj/assertj-core/3.1.0/org/assertj/core/api/AbstractListAssert.html#isSortedAccordingTo-java.util.Comparator-)

It would be something along these lines:
```
list shouldBeSortedAccordingTo Comparator.comparingInt { it.position }
```
or
```
list shouldBeSortedBy Comparator.comparingInt { it.position }
```

This could then be chained to a structure like this
```
list.shouldNotBeEmpty()
.shouldHaveSize(10)
.shouldBeSortedAccordingTo(Comparator.comparing<Slot, Int> { it.position })
```

### Additional contract requirements

- The sorted-order assertion for collections is named `shouldBeSortedAccordingTo`, and it takes the `Comparator` as its argument. The name `shouldBeSortedBy` is not part of this request.
- The assertion passes when each element is not ordered after the element that follows it under the comparator, and fails otherwise. Adjacent elements that compare as equal are acceptable.
- The assertion returns the collection it was called on, so it can be chained with other collection assertions.
