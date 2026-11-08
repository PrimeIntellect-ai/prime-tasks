Hashes not serialized in external references
I suspect that there might by something wrong with the `BomJsonGenerator14`.
It does not output hashes which are part of external references.

**Steps to reproduce**

The following complete Java program, using

- cyclonedx-core-java v7.1.5
- Windows 10 64bit
- Java 8

```java
import java.util.Arrays;

import org.cyclonedx.generators.json.BomJsonGenerator14;
import org.cyclonedx.model.Bom;
import org.cyclonedx.model.Component;
import org.cyclonedx.model.ExternalReference;
import org.cyclonedx.model.Hash;


class Scratch
{
    public static void main(String[] args)
    {
        ExternalReference extRef = new ExternalReference();
        extRef.setType(ExternalReference.Type.BOM);
        extRef.setUrl("https://example.org/support/sbom/portal-server/1.0.0");
        extRef.setComment("An external SBOM that describes what this component includes");
        Hash md5 = new Hash(Hash.Algorithm.MD5, "2cd42512b65500dc7ba0ff13490b0b73");
        Hash sha1 = new Hash(Hash.Algorithm.SHA1, "226247b40160f2892fa4c7851b5b913d5d10912d");
        Hash sha256 = new Hash(Hash.Algorithm.SHA_256, "09a72795a920c1a9c0209cfb8395f8d97089832d249cba8c0938a3423b3ed1d1");
        extRef.setHashes(Arrays.asList(md5, sha1, sha256));

        Component component = new Component();
        component.setGroup("org.example");
        component.setName("mylibrary");
        component.setType(Component.Type.LIBRARY);
        component.setVersion("1.0.0");
        component.addExternalReference(extRef);

        Bom bom = new Bom();
        bom.addComponent(component);

        String json = new BomJsonGenerator14(bom).toJsonString();
        System.out.println(json);
    }
}
```

Here's the **actual output (green)** vs. the **expected output (red)**:

```diff
{
  "bomFormat" : "CycloneDX",
  "specVersion" : "1.4",
  "version" : 1,
  "components" : [
    {
      "group" : "org.example",
      "name" : "mylibrary",
      "version" : "1.0.0",
      "externalReferences" : [
        {
          "type" : "bom",
          "url" : "https://example.org/support/sbom/portal-server/1.0.0",
-          "comment" : "An external SBOM that describes what this component includes",
+          "comment" : "An external SBOM that describes what this component includes"
-          "hashes" : [
-            {
-              "alg" : "MD5",
-              "content" : "2cd42512b65500dc7ba0ff13490b0b73"
-            }, {
-              "alg" : "SHA-1",
-              "content" : "226247b40160f2892fa4c7851b5b913d5d10912d"
-            }, {
-              "alg" : "SHA-256",
-              "content" : "09a72795a920c1a9c0209cfb8395f8d97089832d249cba8c0938a3423b3ed1d1"
-            }
-          ]
        }
      ],
      "type" : "library"
    }
  ]
}
```

I found some [test data](https://github.com/CycloneDX/cyclonedx-core-java/blob/cyclonedx-core-java-7.1.5/src/test/resources/1.4/valid-external-reference-1.4.json#L23-L28) which indicates that my code above should work, but it seems the corresponding tests only test parsing it, not generating. When I look at the objects in a debugger just before serialization, they look fine and include the hashes. However, the generated JSON does not include the hashes.

Please let me know if you need anything else or if I can assist somehow. Thanks for looking into this!
