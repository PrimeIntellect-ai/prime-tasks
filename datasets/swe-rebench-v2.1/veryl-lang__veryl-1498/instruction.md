Module recrsion (recutsion) bugs
A compilation bug in the following code:

```systemverilog
module psel #(
    param DIM: u32 = 8,
) (
    i_data: input  logic<DIM>    ,
    o_mask: output logic<DIM>    ,
    o_set : output logic      = _,
) {

    if (DIM == 1) :gen_base_case {
        assign o_set  = i_data[0];
        assign o_mask = i_data;
    } else {
        // Get split (2 -> 1, 3 -> 2, 4 -> 2, etc)
        const SPLIT_POINT: u32 = 1 << ($clog2(DIM) - 1);
        const TOP_SIZE    : u32 = DIM - SPLIT_POINT;
        // const SPLIT_POINT: u32 = DIM / 2; --- THIS WORKS

        var top_mask: logic<TOP_SIZE>;
        var top_set : logic          ;

        var bot_mask  : logic<SPLIT_POINT>;
        var bot_masked: logic<SPLIT_POINT>;
        var bot_set   : logic             ;

        assign bot_masked = if top_set ? '0 : bot_mask;
        assign o_mask     = {top_mask, bot_masked};
        assign o_set      = top_set | bot_set;

        inst u_top: psel #(
            DIM: TOP_SIZE,
        ) (
            i_data: i_data[msb:SPLIT_POINT],
            o_mask: top_mask               ,
            o_set : top_set                ,
        );

        inst u_bot: psel #(
            DIM: SPLIT_POINT,
        ) (
            i_data: i_data[SPLIT_POINT - 1:0],
            o_mask: bot_mask                 ,
            o_set : bot_set                  ,
        );
    }
}
```

This results in an `infinite_recursion` error on `inst u_bot`.  This, despite the fact that the recursion is a finite chain terminating at `1`, the base case.  You'll see that what `1 << ($clog2(DIM) - 1)` is setting `SPLIT_POINT` to be the largest power of two strictly less than `DIM`.  Not only does this value exist for all `DIM > 1`, but it clearly terminates at `1`.  Further, adding a base case for `DIM == 0` does not fix this bug.

For this specific module, there's no reason to not just go with `SPLIT_POINT = DIM / 2`.  But for other modules it makes sense to split at powers of two (consider, for example, a one hot decoder).

Second bug is that, for some reason, the LSP message is `Semantic Error: infinite instance recustion is detected`.  So that's an easy fix: recustion -> recursion.
