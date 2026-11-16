Support default field values other than None
There's a small issue that pops up when you have non-None default values. I see the issues happens on [HIDDEN] but I'm not sure the best way to resolve. (failed hard on test_embeddable_json_schema)

@dataclass
class DefaultVal(JsonSchemaMixin):
    a: int
    b: Optional[int] = 5

should pass:

assert DefaultVal.from_dict({'a': 1}) == DefaultVal(a=1)
