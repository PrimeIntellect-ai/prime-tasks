gedcom query panic: cannot create Husband without a family
Panic when trying to merge 2 simple Gedcom-files, 3 individuals and 1 family each with the command
gedcom query -gedcom a.ged -gedcom b.ged -format gedcom 'MergeDocumentsAndIndividuals(Document1, Document2)'

panic: cannot create Husband without a family

goroutine 1 [running]:
github.com/elliotchance/gedcom.needsFamily(...)
	/tmpdata/gedcomTool/gedcomSRC/decoder.go:387
github.com/elliotchance/gedcom.newNodeWithChildren(0x0, 0x0, 0x1, 0x672f7e, 0x4, 0x673d58, 0x7, 0x0, 0x2, 0xc0000b15f7, ...)
	/tmpdata/gedcomTool/gedcomSRC/decoder.go:312 +0x3ba9
github.com/elliotchance/gedcom.NewNode(...)
	/tmpdata/gedcomTool/gedcomSRC/decoder.go:265
github.com/elliotchance/gedcom.(*SimpleNode).ShallowCopy(0xc000162230, 0x0, 0x0)
	/tmpdata/gedcomTool/gedcomSRC/simple_node.go:165 +0x17c
github.com/elliotchance/gedcom.DeepCopy.func1(0x6cd000, 0xc000099aa0, 0x0, 0x6cce80, 0xc00018a6c0)
	/tmpdata/gedcomTool/gedcomSRC/copy.go:33 +0x31
github.com/elliotchance/gedcom.filter(0x6cd000, 0xc000099aa0, 0x6843e0, 0xc0001076f0, 0x6cce80, 0xc00018a6c0)
	/tmpdata/gedcomTool/gedcomSRC/filter.go:56 +0x55
github.com/elliotchance/gedcom.filter(0x6cce80, 0xc0000a6f00, 0x6843e0, 0xc0001076f0, 0x6cd680, 0x203000)
	/tmpdata/gedcomTool/gedcomSRC/filter.go:86 +0x1df
github.com/elliotchance/gedcom.Filter(...)
	/tmpdata/gedcomTool/gedcomSRC/filter.go:52
github.com/elliotchance/gedcom.DeepCopy(0x6cce80, 0xc0000a6f00, 0x1, 0x1)
	/tmpdata/gedcomTool/gedcomSRC/copy.go:32 +0xf7
github.com/elliotchance/gedcom.MergeNodeSlices(0xc0000f6600, 0xd, 0x10, 0xc0000f6700, 0xa, 0x10, 0x6843e8, 0xc00018a5c0, 0x3, 0x4)
	/tmpdata/gedcomTool/gedcomSRC/merge.go:133 +0x121
github.com/elliotchance/gedcom.MergeDocumentsAndIndividuals(0xc000150850, 0xc0001631f0, 0x6843e8, 0xc00014e6e0, 0x2, 0xc00016a830, 0x1)
	/tmpdata/gedcomTool/gedcomSRC/merge.go:254 +0x131
github.com/elliotchance/gedcom/q.(*MergeDocumentsAndIndividualsExpr).Evaluate(0x896f18, 0xc0000a6ae0, 0x661980, 0xc000150850, 0xc000099500, 0x2, 0x2, 0x86e3a0, 0x7f5f25cc07d0, 0x0, ...)
	/tmpdata/gedcomTool/gedcomSRC/q/merge_documents_and_individuals_expr.go:38 +0x3c9
github.com/elliotchance/gedcom/q.(*CallExpr).Evaluate(0xc00009b7d0, 0xc0000a6ae0, 0x661980, 0xc000150850, 0x0, 0x0, 0x0, 0x661980, 0xc000150850, 0x0, ...)
	/tmpdata/gedcomTool/gedcomSRC/q/call_expr.go:10 +0x73
github.com/elliotchance/gedcom/q.(*Statement).Evaluate(0xc00009b800, 0xc0000a6ae0, 0x661980, 0xc000150850, 0x661980, 0xc000150850, 0x0, 0x0)
	/tmpdata/gedcomTool/gedcomSRC/q/statement.go:21 +0xa8
github.com/elliotchance/gedcom/q.(*Engine).Evaluate(0xc0000a6ae0, 0xc00016a7d0, 0x2, 0x2, 0x2, 0xc00016a7d0, 0x1, 0x2)
	/tmpdata/gedcomTool/gedcomSRC/q/engine.go:34 +0x401
main.runQueryCommand()
	/tmpdata/gedcomTool/gedcomSRC/cmd/gedcom/query.go:64 +0x598
main.main()
	/tmpdata/gedcomTool/gedcomSRC/cmd/gedcom/main.go:46 +0x1e6

### Additional contract requirements

Copying and merge operations that may create GEDCOM nodes requiring document context must allow callers to provide a destination document. That context must be available throughout the operation, including to node-merge callbacks, so a copied family-related node can be created without a panic. The destination document is also used to attach newly created nodes.

The destination document supplied to a copying operation is the document associated with every newly created document-dependent node. A merge callback receives the same destination document supplied to its enclosing merge operation.

The public Go call forms for these operations are:

```go
DeepCopy(node Node, document *Document) Node
(*FilterFlags).Filter(node Node, document *Document) Node
Filter(root Node, document *Document, fn FilterFunction) Node
Flatten(document *Document, node Node) Nodes
(IndividualNodes).Merge(other IndividualNodes, document *Document, options *IndividualNodesCompareOptions) (IndividualNodes, error)
MergeNodes(left Node, right Node, document *Document) (Node, error)
MergeNodeSlices(left Nodes, right Nodes, document *Document, mergeFn MergeFunction) Nodes
MergeDocuments(left *Document, right *Document, document *Document, mergeFn MergeFunction) *Document
type MergeFunction func(left Node, right Node, document *Document) Node
IndividualBySurroundingSimilarityMergeFunction(minimumSimilarity float64, options SimilarityOptions) MergeFunction
```
