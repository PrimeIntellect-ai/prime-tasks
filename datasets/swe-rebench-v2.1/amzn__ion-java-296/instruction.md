IonSequenceLite.subList does not throw when passed start or end values that are out of range
According to the [List javadoc](https://docs.oracle.com/javase/7/docs/api/java/util/ArrayList.html#subList(int,%20int)), the subList method should throw:

```
    IndexOutOfBoundsException - if an endpoint index value is out of range (fromIndex < 0 || toIndex > size)
    IllegalArgumentException - if the endpoint indices are out of order (fromIndex > toIndex)
```

However, instead what happens is that we are returned a `List<IonValue>` instance with an invalid size.  This is demonstrated with the following:

```
public class ScratchPad {
    static final IonSystem SYSTEM = IonSystemBuilder.standard().build();

    @Test
    public void sizeMe() {
        List<IonValue> list = SYSTEM.newList(new int[] { 1, 2, 3}).subList(0, 3000);
        System.out.println(list.size()); // 3000 - what?!?!
    }
}
```
