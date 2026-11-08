Accessing globals in macros (again)
The solution of passing a `_context` was a bit overkill as it passes too much data. It doesn't just pass globals, it's passing in local variables. I'm defining globals as the set of key/value pairs returned by the `getGlobalVariables` method overridden on the class `AbstractExtension`. These are the true global variables.

```
    @Override
    public Map<String, Object> getGlobalVariables() {
        final Map<String, Object> globals = new HashMap<>();
        globals.put("DATE_TIME_FULL", DateFormat.FULL);
        globals.put("DATE_TIME_LONG", DateFormat.LONG);
        globals.put("DATE_TIME_MEDIUM", DateFormat.MEDIUM);
        globals.put("DATE_TIME_SHORT", DateFormat.SHORT);
        globals.put("DATE_TIME_NONE", -1);
        return globals;
    }
```

In that same `AbstractExtension` class I'm providing a filter, which I expect to use those globals with.

```
    @Override
    public Map<String, Filter> getFilters() {
        final Map<String, Filter> filters = new HashMap<>();
        filters.put("dateTime", new DateTimeFilter());
        return filters;
    }
```

I encounter the classical globals/macros issue when I trey to wrap my filter into a macro, and within that macro use any specified global. I only want transparent and easy access to the TRUE globals, instead, I have to munge up with a _context parameter...

```
{% macro printDate(timezone, timestamp, _context) %}{{ timestamp ? (timestamp | dateTime(timezone, _context.DATE_TIME_LONG, _context.DATE_TIME_NONE)) : "-" }}{% endmacro %}
```
versus
```
{% macro printDate(timezone, timestamp) %}{{ timestamp ? (timestamp | dateTime(timezone, DATE_TIME_LONG, DATE_TIME_NONE)) : "-" }}{% endmacro %}
```

Requested fix: please make `getGlobalVariables` truly global without requiring usage of `_context`.
