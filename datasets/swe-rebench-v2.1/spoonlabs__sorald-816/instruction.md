S1176: tailor S1176 (Javadoc)
easy solution: we remove the `api` FQN constraint for S1176.

### Additional contract requirements

Sorald's `mine` command must support configuring individual SonarJava rules through a new
CLI option `--rule-parameters`, exposed as the public constant
`sorald.Constants.ARG_RULE_PARAMETERS`. The option takes the path to a JSON file with the
following format:

{
    "<RULE_KEY>": {
        "<RULE_PROPERTY_NAME>": "<VALUE>"
    }
}

The parameters are applied to the corresponding rules when mining. For example, S1176
(UndocumentedApiCheck) has a `forClasses` parameter that restricts which classes it applies
to; passing `{"S1176": {"forClasses": "**"}}` makes S1176 report classes outside `api`
packages. When the option is not passed, rules keep their default parameters; in particular,
S1176 keeps its default `api` FQN constraint and does not report classes outside `api`
packages.


- When mining reports an S1176 violation, the output includes the literal `S1176=1`.
