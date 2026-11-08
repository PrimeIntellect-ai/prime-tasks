Avatar: Error rendering label with only numbers
### Describe the bug

I have an issue where the value passed to the attribute label is only numbers or anything different as letters, the current version throws an exception with the message



`java.lang.StringIndexOutOfBoundsException: String index out of range: 0
	at java.base/java.lang.StringLatin1.charAt(StringLatin1.java:47)
	at java.base/java.lang.String.charAt(String.java:693)
	at org.primefaces.component.avatar.AvatarRenderer.calculateLabel(AvatarRenderer.java:128)
	at org.primefaces.component.avatar.AvatarRenderer.encodeEnd(AvatarRenderer.java:58)
	at javax.faces.component.UIComponentBase.encodeEnd(UIComponentBase.java:595)
	at javax.faces.component.UIComponent.encodeAll(UIComponent.java:1654)
	at javax.faces.render.Renderer.encodeChildren(Renderer.java:152)`

Reviewing the source code of the avatar component I found that the component is assuming that only letters are included in the label if not, the call of the following method throws the exception

```java
protected String calculateLabel(FacesContext context, Avatar avatar)  {

        String value = avatar.getLabel();

        if (value == null || value.length() <= 2) {
            return value;
        }
        [HIDDEN]
        [HIDDEN]
    }
```



### Reproducer

_No response_

### Expected behavior

The label should be taken as an string of characters no matters if its only numbers and not letters on it.

### PrimeFaces edition

Elite

### PrimeFaces version

11.0.9

### Theme

Rain

### JSF implementation

Mojarra

### JSF version

2.2

### Java version

11

### Browser(s)

Chrome

### Additional contract requirements

- For labels longer than two characters with no uppercase letters, render the first character of the label (for example, `8675309` renders as `8`, `1234` as `1`, `888 7666` as `8`, and `41235 5asdd` as `4`).
- Labels of at most two characters must be rendered unchanged, including numeric labels.
