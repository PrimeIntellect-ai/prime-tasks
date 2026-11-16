Before spec messages not rendered for multi-row table-driven specs
### Expected behavior
Calls to `Gauge.writeMessage`  in a before spec hook should always result in a message at the top of the spec

### Actual behavior
For table driven specs, the message is only rendered when the table has a single row

**Multi-item table**
<img width="698" alt="image" src="https://user-images.githubusercontent.com/41190821/84746609-26e60300-afae-11ea-8543-50b1e8d7567b.png">

**Single-item table**
<img width="793" alt="image" src="https://user-images.githubusercontent.com/41190821/84746675-42510e00-afae-11ea-9d96-ec6a18822ae8.png">

### Steps to reproduce
1. Create a before spec hook which calls `Gauge.writeMessage`
```java
    @BeforeSpec
    public void beforeSpec() {
        Gauge.writeMessage("Before spec message");
    }

```
2. Create a spec with a multiple table items (and create the dummy step referenced)
```markdown
# Demo the bug with tables
Tags: demo, demo-bug

  | text |
  |------|
  | foo  |
  | bar  |

## Print scenario
* Print the text <text>
```
3. Inspect the report, the message does not appear

### Gauge version
```
Gauge version: 1.0.8
Commit Hash: 28617ea

Plugins
-------
html-report (4.0.10)
java (0.7.7)
```
