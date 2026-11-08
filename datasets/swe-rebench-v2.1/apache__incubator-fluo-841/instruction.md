Add copyTo() method to bytes
For data serialization use cases, a user may want to copy multiple Bytes objects to a byte array.   The current options for that are to call Bytes.toArray() or use the Bytes.byteAt() method.  If Bytes had a `copyTo(byte[] dest, int offset)`   method then it could support this use case more efficiently.  The following is an example.

```java
Bytes field1 = Bytes.of("foo");
Bytes field2 = Bytes.of("bar");

byte[] dest = new byte[field1.length() + field2.lenght() + 1];

field1.copyTo(dest, 0);
dest[field1.lenght()] = ':';
field2.copyTo(dest, field1.lenght()+1);
```
