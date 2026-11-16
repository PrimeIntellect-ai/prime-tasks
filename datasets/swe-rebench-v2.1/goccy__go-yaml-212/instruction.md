“cannot find anchor by alias name”
I'm working with `github.com/goccy/go-yaml` because I'm interested in loading a YAML config file that includes YAML 1.2 anchors, aliases, and extensions. For instance, the YAML below shows what I'm hoping to load. Having the ability to replicate certain fields like this will reduce a great deal of configuration duplication.

```
%YAML 1.2
---
foo:
 <<: &test-anchor
   K1: "One"
 K2: "Two"

bar:
 <<: *test-anchor
 K3: "Three"
```
Given everything that this package can do I assume it's possible to achieve this. However, when I `Unmarshal()` YAML such as above I receive the error: “cannot find anchor by alias name test-anchor.”

The YAML processes correctly with other tools so I believe I have the syntax correct.

Below is simple test code for exercising the above. In this test code I'm attempting to demonstrate processing the aliases in the YAML blurb by unmarshaling it and then marshaling the resulting structure as printable YAML again.

Am I missing something in my YAML? Have I misunderstood the abilities of `goccy/go-yaml` or used the incorrect configuration?

```
package main

import (
	"fmt"
	"github.com/goccy/go-yaml"
)

func main() {
	type foo struct {
		K1 string
		K2 string
	}

	type bar struct {
		K1 string
		K3 string
	}

	type doc struct {
		Foo foo
		Bar bar
	}

	yml := `
%YAML 1.2
---
foo:
 <<: &test-anchor
   K1: "One"
 K2: "Two"

bar:
 <<: *test-anchor
 K3: "Three"
`
	var v doc
	var err error
	if err = yaml.Unmarshal([]byte(yml), &v); err != nil {
		fmt.Println(err.Error())
	} else {
		bytes, err := yaml.Marshal(v)
		if err != nil {
			fmt.Println(err.Error())
		} else {
			fmt.Println(string(bytes))
		}
	}
}
```
