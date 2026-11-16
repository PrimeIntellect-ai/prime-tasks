`InstanceOfAssertFactories.array` and `InstanceOfAssertFactories.array2D` expect array type parameter instead of the one for their elements
Currently, `InstanceOfAssertFactories.array` and `InstanceOfAssertFactories.array2D` must be used in the following way:

```java
Object array = new Integer[] { 0, 1 };
assertThat(array).asInstanceOf(array(Integer[].class)).containsExactly(0, 1);

Object array2D = new Integer[][] { { 0, 1 }, { 2, 3 } };
assertThat(array2D).asInstanceOf(array2D(Integer[][].class)).hasDimensions(2, 2);
```

where the array type is provided as a parameter.

However, factories like `collection` or `list` expect the element type instead:

```java
Object list = List.of("Homer", "Marge", "Bart", "Lisa", "Maggie");

assertThat(list).asInstanceOf(collection(String.class)).contains("Bart", "Lisa");
assertThat(list).asInstanceOf(list(String.class)).contains("Bart", "Lisa");
```

We should change the type parameter for `array` and `array2d` to be the element type.
