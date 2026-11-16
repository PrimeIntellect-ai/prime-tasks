DataTable: column footer width doesn't follow column width
### Describe the bug

When migrating Primefaces to version 15 I ran into a problem where the column footer width is different from the column width.

### Reproducer

Here's a sample xhtml and bean:

xhtml:
```
<!DOCTYPE html>
<html lang="pt-BR"
      xmlns="http://www.w3.org/1999/xhtml"
      xmlns:h="http://xmlns.jcp.org/jsf/html"
      xmlns:f="http://xmlns.jcp.org/jsf/core"
      xmlns:p="http://primefaces.org/ui">
<h:head>

</h:head>
<h:body>
    <f:view>
    <div class="ui-fluid card">
        <h:form>
            <div class="p-grid p-col-12">
                <p:dataTable value="#{testWebBean.testDTOs}"
                             var="test"
                             scrollable="true"
                             scrollHeight="400"
                             rowIndexVar="idx"
                             styleClass="ui-datatable-gridlines ui-datatable-striped ui-datatable-sm"
                             reflow="true">
                    <p:column width="5" styleClass="datatable-center">
                        <h:outputText value="#{idx + 1}"/>
                    </p:column>
                    <p:column width="15" styleClass="datatable-center">
                        <f:facet name="header">col 1</f:facet>
                        test
                    </p:column>
                    <p:column width="100">
                        <f:facet name="header">col 2</f:facet>

                        <h:outputText id="value1" value="#{test.value1}" />

                        <f:facet name="footer">
                            <div class="p-grid">
                                <div class="p-col-12 ">
                                    <h:outputText value="some text" />
                                </div>
                                <div class="p-col-12 " style="padding-top: 7px;">
                                    <h:outputText value="some more text" />
                                </div>
                            </div>
                        </f:facet>
                    </p:column>
                    <p:columns id="sub"
                               value="#{testWebBean.subs}"
                               var="sub"
                               width="20"
                               headerText="teste"
                               rendered="true"
                               columnIndexVar="idx2">
                        <f:facet name="header">
                            <div>
                                <h:outputText value="#{idx2 + 1}" />
                            </div>
                            <div>
                                <p:selectBooleanCheckbox />
                            </div>
                        </f:facet>

                        <h:panelGroup>
                            <div>
                                <p:selectBooleanCheckbox value="#{sub.selected}" />
                            </div>
                        </h:panelGroup>

                        <f:facet name="footer">
                            <div class="p-grid">
                                <div class="p-col-12">
                                    <p:selectBooleanCheckbox />
                                </div>
                                <div class="p-col-12" style="padding-top: 8px">
                                    test
                                </div>
                            </div>
                        </f:facet>
                    </p:columns>
                    <p:column headerText="col 3" width="50">
                        <h:outputText value="#{test.value2}" />
                    </p:column>
                </p:dataTable>
            </div>
        </h:form>
    </div>

    </f:view>
</h:body>
</html>
```
bean:
```
import jakarta.annotation.PostConstruct;
import jakarta.inject.Named;
import org.omnifaces.cdi.ViewScoped;

import java.io.Serializable;
import java.util.ArrayList;
import java.util.List;

@ViewScoped
@Named("testWebBean")
public class TestWebBean implements Serializable {

    private List<TestDTO> testDTOs = new ArrayList<>();
    private List<TestSubDTO> subs = new ArrayList<>();

    @PostConstruct
    public void init() {
        for (int i=0; i<50; i++) {
            var testDTO = new TestDTO();
            testDTO.setValue1("Test " + i + "-1");
            testDTO.setValue2("Test " + i + "-2");
            testDTOs.add(testDTO);
        }

        subs.add(new TestSubDTO());
        subs.add(new TestSubDTO());
        subs.add(new TestSubDTO());
        subs.add(new TestSubDTO());
        subs.add(new TestSubDTO());
    }

    public List<TestDTO> getTestDTOs() {
        return testDTOs;
    }

    public List<TestSubDTO> getSubs() {
        return subs;
    }

    public class TestDTO implements Serializable {

        private String value1;
        private String value2;

        public String getValue1() {
            return value1;
        }

        public void setValue1(String value1) {
            this.value1 = value1;
        }

        public String getValue2() {
            return value2;
        }

        public void setValue2(String value2) {
            this.value2 = value2;
        }
    }

    public class TestSubDTO implements Serializable {
        private boolean selected;

        public boolean isSelected() {
            return selected;
        }

        public void setSelected(boolean selected) {
            this.selected = selected;
        }
    }
}
```

When using primefaces 11, it looks like this:

![Image](https://github.com/user-attachments/assets/9f8b0a82-76bc-4f9b-814f-c30fbc9c72cd)

But after changing to primefaces 15, it looks like this:

![Image](https://github.com/user-attachments/assets/051d99a5-d61d-42f4-8d7d-5ab51f011c44)

### Expected behavior

The width of the footers should follow the width of the column, just like it did on version 11.

### PrimeFaces edition

None

### PrimeFaces version

15.0.0

### Theme

Poseidon

### JSF implementation

Mojarra

### JSF version

4.0.1

### Java version

21

### Browser(s)

_No response_
