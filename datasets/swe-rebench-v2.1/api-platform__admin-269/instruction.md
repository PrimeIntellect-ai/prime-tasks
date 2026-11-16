Range filter changes [] style to dot notation
If use standard filters to achieve range filter functionality, i.e.:
```
<Filter {...props}>
    <SelectInput
        source='year[gte]'
        label="Year from"
        choices={getYears()}
        alwaysOn
    />
</Filter>
```
as a result you will get api request: year.gte=2002 instead of required year[gte]=2002
