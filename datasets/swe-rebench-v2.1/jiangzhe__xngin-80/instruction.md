Greedy join reorder
Implement basic join reorder framework with greedy algorithm

### Additional contract requirements

The join reorder framework is exposed through the following public API of the `xngin_plan` crate.

- A public function `join_reorder<R, F>(plan: &mut QueryPlan, f: F) -> Result<()>` in module `xngin_plan::join::reorder`, where `R: Reorder` and `F: FnMut() -> R`. It replaces every `JoinGraph` operator in the plan (including attached subqueries) with a join tree produced by the `Reorder` implementation returned by the closure.
- A public trait `Reorder` in module `xngin_plan::join::reorder` with a method `reorder(self, graph: &Graph) -> Result<Op>` that returns the root operator of the reordered join subtree for the supplied join graph.
- A public trait `Estimate` in module `xngin_plan::join::estimate` with methods:
  - `estimated_qry_rows(&mut self, vset: VertexSet) -> Result<f64>`, returning the estimated row count of the query represented by `vset`.
  - `estimated_join_rows(&mut self, kind: JoinKind, l_vset: VertexSet, r_vset: VertexSet, e_vset: VertexSet, cond: &[Expr], filt: &[Expr]) -> Result<f64>`, returning the estimated row count of the described join.
- A public struct `Goo<E>` in module `xngin_plan::join::reorder` with a constructor `Goo::new(est: E) -> Self`. When `E: Estimate`, `Goo<E>` implements `Reorder` and greedily combines join sets so that the intermediate result of each join is minimal.
- A public struct `Sequential` in module `xngin_plan::join::reorder` that implements `Reorder` by reconstructing the join tree in the original join order.

The types `QueryPlan`, `Op`, `Graph`, `VertexSet`, `JoinKind` and `Result` are the existing public types of the `xngin_plan` crate (`xngin_plan::query::QueryPlan`, `xngin_plan::op::Op`, `xngin_plan::join::graph::Graph`, `xngin_plan::join::graph::VertexSet`, `xngin_plan::join::JoinKind`, `xngin_plan::error::Result`), and `Expr` is `xngin_expr::Expr`.
