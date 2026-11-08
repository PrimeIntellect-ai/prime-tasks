Distributions uses an old version of Rmath
R v-4.1.3 (released 10 March 2022) improved accuracy of distribution quantile functions, but Distributions continues to use an older version of Rmath.

Example:
quantile(Beta(0.01,0.1),0.92)
returns 1.0 instead of 0.780301421091985
Older versions of R at least threw a warning "full precision may not have been achieved in 'qbeta'", but Julia gives no indication that the result is completely wrong.
