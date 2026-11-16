Problem of escaping in the sheet name
Hi,

In the version 0.15.2

In the node `      <definedName function="false" hidden="true" localSheetId="0" name="_xlnm._FilterDatabase" vbProcedure="false">&apos;T&O&apos;!$A$1:$D$1</definedName>` the sheet name is not escaped.

The sheetname is correctly escaped here:
`      <sheet name="T&amp;O" r:id="rId3" sheetId="1"/>`

The consequence, the Excel file cannot be read, it's corrupt.

`<?xml version="1.0" encoding="UTF-8"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
   <workbookPr date1904="false"/>
   <bookViews>
      <workbookView activeTab="0"/>
   </bookViews>
   <sheets>
      <sheet name="T&amp;O" r:id="rId3" sheetId="1"/>
   </sheets>
   <definedNames>
      <definedName function="false" hidden="true" localSheetId="0" name="_xlnm._FilterDatabase" vbProcedure="false">&apos;T&O&apos;!$A$1:$D$1</definedName>
   </definedNames>
</workbook>`

Thank you
