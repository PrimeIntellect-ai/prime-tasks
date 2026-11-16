Unclear how to show selected column with dynamic row updates
In the features example, there is a column that shows automatically to indicate which rows the user has selectable. As I understand, that column does not need to be manually specified - you simply set `SelectableRows(true)` on the model. I'm trying to get that column to display when the row data is being dynamically populated.

The table is created like this:
```
// this is the underlying bubbletea model
type model struct {
	table    projectsTable
	projects []Project
}

type projectsTable struct {
	model table.Model
}

func createProjectsTable() projectsTable {
	columns := generateColumns()
	rows := generateRowsFromProjects([]Project{})

	model := projectsTable{
		model: table.New(columns).
			WithRows(rows).
			SelectableRows(true).
			WithSelectedText(" ", "Y").
			Focused(true).
			SortByAsc(columnLastModified),
	}
	return model
}

func generateColumns() []table.Column {
	columns := []table.Column{
		table.NewFlexColumn(columnName, "Name", 1),
		table.NewFlexColumn(columnPath, "Path", 3),
		table.NewColumn(columnLastModified, "Last Modified", 20),
	}
	return columns
}

func generateRowsFromProjects(projects []Project) []table.Row {
	rows := []table.Row{}
	for _, entry := range projects {
		row := table.NewRow(table.RowData{
			columnName:         entry.Name,
			columnPath:         entry.Path,
			columnLastModified: entry.LastModified.Format("2006-01-02 15:04:05"),
		})
		rows = append(rows, row)
	}

	return rows
}
```

In the initial state where `rows` is empty, the selected column displays correctly

But I have a keybinding that lets the user regenerate the rows when `m.projects` data is updated:
```
m.table.model = m.table.model.WithRows(generateRowsFromProjects(m.projects)).WithColumns(generateColumns())
```

When that happens, the table updates with the correct data but the select column is no longer visible

Is there something special that needs to be done when the rows are being updated/replaced using `WithRows()`? I couldn't find anything in the documentation about this as it seems everything related to the select column is handled automatically under the hood
