Date in TIME_IN_MILLIS not serialized as number
**Describe the bug**
According to  jsonb-api ([JsonbDateFormat#TIME_IN_MILLIS](https://github.com/eclipse-ee4j/jsonb-api/blob/703826016ebd5aa439d56d272c073e1961415ad4/api/src/main/java/jakarta/json/bind/annotation/JsonbDateFormat.java#L61)), a date formatted with the `TIME_IN_MILLIS` formatter shall be serialized as a number. This is not the case. Such dates are serialized as strings.

[HIDDEN]

**To Reproduce**
Serialize an instance of:
```java
public class Dummy {

    @JsonbDateFormat(value = JsonbDateFormat.TIME_IN_MILLIS)
    private OffsetDateTime date;

    public OffsetDateTime getDate(){ return date;}
    public void setDate(OffsetDateTime date){  this.date = date;}
}
```

The JSON will looks like
```json
{ "date": "1638953417522" }
```

**Expected behavior**

JSON should looks like
```json
{ "date": 1638953417522 }
```

**System information:**
 - OS: Linux
 - Java Version: 11
 - Yasson Version: 2.0.4

**Additional context**
Deserialization works fine, with both representation:

```json
{ "date": 1638953417522 }

{ "date": "1638953417522" }

```
