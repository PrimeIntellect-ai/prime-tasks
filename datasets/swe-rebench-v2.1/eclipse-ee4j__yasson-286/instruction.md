Inheriting from class with package level modifier leads to IllegalAccessException
The following simple example:
``` java
import javax.json.bind.Jsonb;
import javax.json.bind.JsonbBuilder;

public class InheritanceExample {

  static class Parent {
    public int id;
  }

  public static class Child extends Parent {
    public String name;
  }

  public static void main( String[] args ) {
    Child child = new Child();
    child.id =1;
    child.name = "name";

    Jsonb jsonb = JsonbBuilder.create();
    System.out.println( jsonb.toJson( child ) );
  }
}
```
Leads to the following error:

```
Exception in thread "main" javax.json.bind.JsonbException: Error getting value on: InheritanceExample$Child@27efef64
	at org.eclipse.yasson.internal.model.GetValueCommand.getValue(GetValueCommand.java:36)
	at org.eclipse.yasson.internal.model.ReflectionPropagation.getValue(ReflectionPropagation.java:73)
	at org.eclipse.yasson.internal.model.PropertyModel.getValue(PropertyModel.java:285)
	at org.eclipse.yasson.internal.serializer.ObjectSerializer.marshallProperty(ObjectSerializer.java:80)
	at org.eclipse.yasson.internal.serializer.ObjectSerializer.serializeInternal(ObjectSerializer.java:61)
	at org.eclipse.yasson.internal.serializer.AbstractContainerSerializer.serialize(AbstractContainerSerializer.java:64)
	at org.eclipse.yasson.internal.Marshaller.serializeRoot(Marshaller.java:148)
	at org.eclipse.yasson.internal.Marshaller.marshall(Marshaller.java:76)
	at org.eclipse.yasson.internal.Marshaller.marshall(Marshaller.java:102)
	at org.eclipse.yasson.internal.JsonBinding.toJson(JsonBinding.java:118)
	at InheritanceExample.main(InheritanceExample.java:20)
Caused by: java.lang.IllegalAccessException: Class org.eclipse.yasson.internal.model.GetFromField can not access a member of class InheritanceExample$Parent with modifiers "public"
	at sun.reflect.Reflection.ensureMemberAccess(Reflection.java:102)
	at java.lang.reflect.AccessibleObject.slowCheckMemberAccess(AccessibleObject.java:296)
	at java.lang.reflect.AccessibleObject.checkAccess(AccessibleObject.java:288)
	at java.lang.reflect.Field.get(Field.java:390)
	at org.eclipse.yasson.internal.model.GetFromField.internalGetValue(GetFromField.java:26)
	at org.eclipse.yasson.internal.model.GetValueCommand.getValue(GetValueCommand.java:34)
	... 10 more
```
Making the `Parent` class public makes this simple example work. However in some cases you might not be able or might not want to make inherited classes visible (public) from the outside.

Should yasson also work for invisible parent classes?

### Additional contract requirements

The required behaviour is that JSON-B serialization and deserialization work for a public class that extends a package-private (non-public) top-level class, including inherited public fields.

Concretely, given a public class `ChildOfPackagePrivateParent` that extends a top-level package-private class `PackagePrivateParent` declaring a public `int id` field, and that itself declares a public `String name` field, with `id = 1` and `name = "SomeName"`:

- `jsonb.toJson(child)` must return `{"id":1,"name":"SomeName"}` — the inherited public field `id` is serialized together with the declared public field `name`.
- `jsonb.fromJson(json, ChildOfPackagePrivateParent.class)` must restore both `id` and `name`.

The required behaviour is defined for top-level package-private parent classes (the `PackagePrivateParent` / `ChildOfPackagePrivateParent` shape). The nested class shape used in the introductory example is not part of the required behaviour.
