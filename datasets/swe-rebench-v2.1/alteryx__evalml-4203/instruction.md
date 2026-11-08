Text columns should be able to to be identified as a perfect match for an ID column

### Additional contract requirements

- ID-column detection must consider text-valued columns, including columns of ordinary strings and categorical columns containing text.
- For this request, a text column is a perfect ID match when every row has a distinct value in that column. Such a column must be eligible for identification as an ID column.
