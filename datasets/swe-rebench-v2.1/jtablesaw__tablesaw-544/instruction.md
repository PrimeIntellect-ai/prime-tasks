Column.countUnique() returns a wrong value after using Column.set()
Hi,

After assigning all values to a previously empty Column, the empty value is still counted by countUnique().  Below is a simple test case demonstrating the issue. The count is correct when the column is created with no size and append() is used (2nd test case).

```
import static org.junit.Assert.*;
import org.junit.Test;
import tech.tablesaw.api.StringColumn;

public class TestTablesawUniqueValues {

	@Test
	public void testUniqueValuesAfterSet() {
		StringColumn col = StringColumn.create("col1", 2);
		col.set(0, "A");
		col.set(1, "B");
		assertEquals("Error in unique() after set()", 2, col.countUnique());
	}

	@Test
	public void testUniqueValuesAfterAppend() {
		StringColumn col = StringColumn.create("col1");
		col.append("A");
		col.append("B");
		assertEquals("Error in unique() after append()", 2, col.countUnique());
	}
}
```
Test result:
java.lang.AssertionError: Error in unique() after set() expected:<2> but was:<3>

Tested on version 0.34.1

Thanks for tablesaw !
