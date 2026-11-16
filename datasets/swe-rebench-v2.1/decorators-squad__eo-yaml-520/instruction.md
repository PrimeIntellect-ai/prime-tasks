Misparsing of mapping entries containing colons
If i parse this:

```
root:
  no-colon-in-value: example.org
  colon-in-value: example.org:80
```

Then the second entry inside root has a key `colon-in-value: example.org` and a value `example.org:80`.

Perhaps the second entry is ambiguous. But that the `example.org` part appears in both the key and the value, which cannot possibly be right!

Here's a small program which reproduces this:

```
import com.amihaiemil.eoyaml.Yaml;
import com.amihaiemil.eoyaml.YamlMapping;
import com.amihaiemil.eoyaml.YamlNode;

import java.io.IOException;

public class ColonMisparseDemo {

    public static void main(String[] args) throws IOException {
        String input = """
                root:
                  no-colon-in-value: example.org
                  colon-in-value: example.org:80
                  """;

        YamlMapping document = Yaml.createYamlInput(input).readYamlMapping();

        YamlMapping root = document.yamlMapping("root");

        for (YamlNode key : root.keys()) {
            YamlNode value = root.value(key);
            System.out.println("[" + key.asScalar().value() + "] = [" + value.asScalar().value() + "]");
        }
    }

}
```

This prints:

```
[no-colon-in-value] = [example.org]
[colon-in-value: example.org] = [example.org:80]
```

I think it should print:

```
[no-colon-in-value] = [example.org]
[colon-in-value] = [example.org:80]
```
