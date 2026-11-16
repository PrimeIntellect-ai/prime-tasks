Allow soft failures for signature validation
@adnanh @moorereason

Heads up, I've spotted an error in the development branch it is only impacting the new Scalr Signature rule.

This is is when using the OR match rule which seems to only work off the top one in the list for example in the below only A would work.:

```
"trigger-rule":{
                "or":[
                        {
                        "match":{
                                "type": "scalr-signature",
                                "secret": "secret **A** inserted here"
                                }
                        },
                        {
                        "match":{
                                "type": "scalr-signature",
                                "secret": "secret **B** inserted here"
                                }
                        }
                ]
        }
```

I think I need to make an update in the sections below related to 'scalr-signature' in order to be able to support the use of the OR and AND MATCH RULES.

I'm going to take a look now but please let me know if you think this might be the case.

@AloysAugustin please also let me know if you by chance spot this message and spot the missing line

**EXTRACT FROM hook.go**

```
// AndRule will evaluate to true if and only if all of the ChildRules evaluate to true
type AndRule []Rules

// Evaluate AndRule will return true if and only if all of ChildRules evaluate to true
func (r AndRule) Evaluate(headers, query, payload *map[string]interface{}, body *[]byte, remoteAddr string) (bool, error) {
	res := true

	for _, v := range r {
		rv, err := v.Evaluate(headers, query, payload, body, remoteAddr)
		if err != nil {
			return false, err
		}

		res = res && rv
		if !res {
			return res, nil
		}
	}

	return res, nil
}

[HIDDEN]
```

### Additional contract requirements

A hook may set `trigger-signature-soft-failures` to `true` to treat signature-validation errors encountered while evaluating an OR rule as non-matches, allowing later alternatives to match. The setting defaults to `false`, preserving hard-error behavior when it is omitted or false. This applies to Scalr signatures as well as payload signature checks. Enabling it must not suppress unrelated rule-evaluation errors.
