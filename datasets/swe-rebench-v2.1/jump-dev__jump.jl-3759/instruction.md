Printing of large vectorized constraints should probably cause output eliding?
This issue is quite similar to the issue of printing a model with large number of constraints (#3651),
it may produce too much output causing just the same issue described in #3651.
Example:
```
using JuMP
import HiGHS

function main()
    NUM_FRAMES = 100
    model = Model(HiGHS.Optimizer);
    @variable(model, x[1:NUM_FRAMES], Bin)
    @variable(model, y[1:NUM_FRAMES], Bin)
    @constraints(model, begin
        x >= y
    end);

    print(model)
end

main()
```
```
$ julia
               _
   _       _ _(_)_     |  Documentation: https://docs.julialang.org
  (_)     | (_) (_)    |
   _ _   _| |_  __ _   |  Type "?" for help, "]?" for Pkg help.
  | | | | | | |/ _` |  |
  | | |_| | | | (_| |  |  Version 1.10.3 (2024-05-22)
 _/ |\__'_|_|_|\__'_|  |  v1.10.3-fix/9607912300 (fork: 354 commits, 329 days)
|__/                   |

julia> using JuMP


julia> import HiGHS

julia> function main()
           NUM_FRAMES = 100
           model = Model(HiGHS.Optimizer);
           @variable(model, x[1:NUM_FRAMES], Bin)
           @variable(model, y[1:NUM_FRAMES], Bin)
           @constraints(model, begin
               x >= y
           end);

           print(model)
       end
main (generic function with 1 method)

julia> main()
Feasibility
Subject to
 [x[1] - y[1], x[2] - y[2], x[3] - y[3], x[4] - y[4], x[5] - y[5], x[6] - y[6], x[7] - y[7], x[8] - y[8], x[9] - y[9], x[10] - y[10], x[11] - y[11], x[12] - y[12], x[13] - y[13], x[14] - y[14], x[15] - y[15], x[16] - y[16], x[17] - y[17], x[18] - y[18], x[19] - y[19], x[20] - y[20], x[21] - y[21], x[22] - y[22], x[23] - y[23], x[24] - y[24], x[25] - y[25], x[26] - y[26], x[27] - y[27], x[28] - y[28], x[29] - y[29], x[30] - y[30], x[31] - y[31], x[32] - y[32], x[33] - y[33], x[34] - y[34], x[35] - y[35], x[36] - y[36], x[37] - y[37], x[38] - y[38], x[39] - y[39], x[40] - y[40], x[41] - y[41], x[42] - y[42], x[43] - y[43], x[44] - y[44], x[45] - y[45], x[46] - y[46], x[47] - y[47], x[48] - y[48], x[49] - y[49], x[50] - y[50], x[51] - y[51], x[52] - y[52], x[53] - y[53], x[54] - y[54], x[55] - y[55], x[56] - y[56], x[57] - y[57], x[58] - y[58], x[59] - y[59], x[60] - y[60], x[61] - y[61], x[62] - y[62], x[63] - y[63], x[64] - y[64], x[65] - y[65], x[66] - y[66], x[67] - y[67], x[68] - y[68], x[69] - y[69], x[70] - y[70], x[71] - y[71], x[72] - y[72], x[73] - y[73], x[74] - y[74], x[75] - y[75], x[76] - y[76], x[77] - y[77], x[78] - y[78], x[79] - y[79], x[80] - y[80], x[81] - y[81], x[82] - y[82], x[83] - y[83], x[84] - y[84], x[85] - y[85], x[86] - y[86], x[87] - y[87], x[88] - y[88], x[89] - y[89], x[90] - y[90], x[91] - y[91], x[92] - y[92], x[93] - y[93], x[94] - y[94], x[95] - y[95], x[96] - y[96], x[97] - y[97], x[98] - y[98], x[99] - y[99], x[100] - y[100]] ∈ MathOptInterface.Nonnegatives(100)
 x[1] binary
 x[2] binary
 x[3] binary
 x[4] binary
 x[5] binary
 x[6] binary
 x[7] binary
 x[8] binary
 x[9] binary
 x[10] binary
 x[11] binary
 x[12] binary
 x[13] binary
 x[14] binary
 x[15] binary
 x[16] binary
 x[17] binary
 x[18] binary
 x[19] binary
 x[20] binary
 x[21] binary
 x[22] binary
 x[23] binary
 x[24] binary
 x[25] binary
 x[26] binary
 x[27] binary
 x[28] binary
 x[29] binary
 x[30] binary
 x[31] binary
 x[32] binary
 x[33] binary
 x[34] binary
 x[35] binary
 x[36] binary
 x[37] binary
 x[38] binary
 x[39] binary
 x[40] binary
 x[41] binary
 x[42] binary
 x[43] binary
 x[44] binary
 x[45] binary
 x[46] binary
 x[47] binary
 x[48] binary
 x[49] binary
[[...101 constraints skipped...]]
 y[51] binary
 y[52] binary
 y[53] binary
 y[54] binary
 y[55] binary
 y[56] binary
 y[57] binary
 y[58] binary
 y[59] binary
 y[60] binary
 y[61] binary
 y[62] binary
 y[63] binary
 y[64] binary
 y[65] binary
 y[66] binary
 y[67] binary
 y[68] binary
 y[69] binary
 y[70] binary
 y[71] binary
 y[72] binary
 y[73] binary
 y[74] binary
 y[75] binary
 y[76] binary
 y[77] binary
 y[78] binary
 y[79] binary
 y[80] binary
 y[81] binary
 y[82] binary
 y[83] binary
 y[84] binary
 y[85] binary
 y[86] binary
 y[87] binary
 y[88] binary
 y[89] binary
 y[90] binary
 y[91] binary
 y[92] binary
 y[93] binary
 y[94] binary
 y[95] binary
 y[96] binary
 y[97] binary
 y[98] binary
 y[99] binary
 y[100] binary
```
There is no eliding, it will still print the entire constraint even if there's 1000 elements,
and in fact it did successfully hand up browser tab with julia's jupyterlab for me.
