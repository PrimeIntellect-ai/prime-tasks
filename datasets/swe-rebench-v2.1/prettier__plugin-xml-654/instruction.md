bracketSameLine not working for long blocks
### bracketSameLine

true

### printWidth

120

### tabWidth

4

### xmlWhitespaceSensitivity

ignore

### xmlSelfClosingSpace

true

### singleAttributePerLine

true

### Input XML

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<jcr:root
    xmlns:sling="http://sling.apache.org/jcr/sling/1.0"
    xmlns:cq="http://www.day.com/jcr/cq/1.0"
    xmlns:jcr="http://www.jcp.org/jcr/1.0"
    xmlns:mix="http://www.jcp.org/jcr/mix/1.0"
    xmlns:nt="http://www.jcp.org/jcr/nt/1.0"
    jcr:mixinTypes="[mix:referenceable]"
    jcr:primaryType="cq:Page"
    jcr:uuid="57d651a5-3bf6-40e0-b7de-67eba070df0a">
    <articlereference
        jcr:created="2023-01-04T16:23:14.182+01:00"
        jcr:createdBy="admin"
        jcr:lastModified="2023-01-04T16:49:32.585+01:00"
        jcr:lastModifiedBy="admin"
        jcr:primaryType="nt:unstructured"
        sling:resourceType="ey-unified-site/components/up-article-reference"
        defaultItemExpansion="true"
        hideArticleRefLabel="Hide"
        showArticleRefLabel="Show"
        textIsRich="true"
    />
    <articlereference2
        short1="Hide"
        short2="Show"
    />
</jcr:root>
```


### Current output XML

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<jcr:root
    xmlns:sling="http://sling.apache.org/jcr/sling/1.0"
    xmlns:cq="http://www.day.com/jcr/cq/1.0"
    xmlns:jcr="http://www.jcp.org/jcr/1.0"
    xmlns:mix="http://www.jcp.org/jcr/mix/1.0"
    xmlns:nt="http://www.jcp.org/jcr/nt/1.0"
    jcr:mixinTypes="[mix:referenceable]"
    jcr:primaryType="cq:Page"
    jcr:uuid="57d651a5-3bf6-40e0-b7de-67eba070df0a">
    <articlereference
        jcr:created="2023-01-04T16:23:14.182+01:00"
        jcr:createdBy="admin"
        jcr:lastModified="2023-01-04T16:49:32.585+01:00"
        jcr:lastModifiedBy="admin"
        jcr:primaryType="nt:unstructured"
        sling:resourceType="ey-unified-site/components/up-article-reference"
        defaultItemExpansion="true"
        hideArticleRefLabel="Hide"
        showArticleRefLabel="Show"
        textIsRich="true"
    />
    <articlereference2
        short1="Hide"
        short2="Show"
    />
</jcr:root>

```


### Expected output XML

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<jcr:root
    xmlns:sling="http://sling.apache.org/jcr/sling/1.0"
    xmlns:cq="http://www.day.com/jcr/cq/1.0"
    xmlns:jcr="http://www.jcp.org/jcr/1.0"
    xmlns:mix="http://www.jcp.org/jcr/mix/1.0"
    xmlns:nt="http://www.jcp.org/jcr/nt/1.0"
    jcr:mixinTypes="[mix:referenceable]"
    jcr:primaryType="cq:Page"
    jcr:uuid="57d651a5-3bf6-40e0-b7de-67eba070df0a">
    <articlereference
        jcr:created="2023-01-04T16:23:14.182+01:00"
        jcr:createdBy="admin"
        jcr:lastModified="2023-01-04T16:49:32.585+01:00"
        jcr:lastModifiedBy="admin"
        jcr:primaryType="nt:unstructured"
        sling:resourceType="ey-unified-site/components/up-article-reference"
        defaultItemExpansion="true"
        hideArticleRefLabel="Hide"
        showArticleRefLabel="Show"
        textIsRich="true" />
    <articlereference2
        short1="Hide"
        short2="Show" />
</jcr:root>

```
