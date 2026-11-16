` _CsvMgr.get_rule_key() ` is supplied with incorrect argument
## Describe the bug

<img width="904" alt="image" src="https://github.com/oscal-compass/compliance-trestle/assets/78010183/a7126df8-fcba-4b15-820f-c555101a60f7">
The above code snippet is from `csv-to-oscal-cd.py`.  The highlighted portion has a potential bug. [HIDDEN] But, this error somehow doesn't generate any serious bug whether when  `component_title` has the same value as `component_description`(in the majority cases) or when they are different. However, the expected key is not in the `_csv_rules_map` dict.

## To Reproduce

Steps to reproduce the behavior:
1. Refer to the below test case:

```
def test_execute_different_component_title_and_description(tmp_path: pathlib.Path) -> None:
    """Test execute missing value."""
    _, section = _get_config_section_init(tmp_path, 'test-csv-to-oscal-cd.config')
    # inject error
    rows = _get_rows('tests/data/csv/ocp4-user.v2.csv')
    row = rows[2]
    assert row[7] == 'OSCO'
    assert row[8] == 'OSCO'
    row[8] = 'IAM'
    assert row[8] == 'IAM'
    component_title = row[7]
    component_description = row[8]
    component_type = row[5]
    rule_id = row[1]
    with mock.patch('trestle.tasks.csv_to_oscal_cd.csv.reader') as mock_csv_reader:
        mock_csv_reader.return_value = rows
        expected_key = (component_title, component_type, rule_id)
        wrong_key = (component_description, component_type, rule_id)
        tgt = csv_to_oscal_cd.CsvToOscalComponentDefinition(section)
        retval = tgt.execute()
        assert retval == TaskOutcome.SUCCESS
        assert wrong_key in tgt._csv_mgr.get_rule_keys()
        assert expected_key in tgt._csv_mgr.get_rule_keys()
```

## Expected behavior

A clear and concise description of what you expected to happen.

## Screenshots / Logs.

If applicable, add screenshots to help explain your problem.

## Environment

- OS: \[e.g. iOS\]
- Python version:
- Installed packages:
