Grading with pipes fails in mysterious ways
```r
# Works
user <- as.expression(rlang::parse_exprs("a <- 2"))
inner_sol <- as.expression(rlang::parse_exprs("a <- 1"))
gradethis::grade_code(correct = "message here", grader_args = list(user_quo = user, solution_quo = inner_sol))

# Works if answer is correct, but throws an error if incorrect.
user <- as.expression(rlang::parse_exprs("1:6 %>% sample(size = 2) %>% sum()"))
inner_sol <- as.expression(rlang::parse_exprs("1:6 %>% sample(size = 2) %>% print"))
gradethis::grade_code(correct = "message here", grader_args = list(user_quo = user, solution_quo = inner_sol))

# Observed errors (depending on the way you get it wrong) include:
# - Error in stop(simpleError(sprintf(msg, ...), call.)) : bad error message
# - "Assertion on '.user' failed: Must be of type 'atomic', not 'expression'.", "Assertion on '.message' failed: Must be of type 'atomic', not 'expression'.", "Assertion on '.incorrect' failed: Must be of type 'atomic', not 'expression'."
# - Error in rhs[[2]] <- lhs : object of type 'symbol' is not subsettable
#    In addition: Warning message:
#    In value[[3L]](cond) : restarting interrupted promise evaluation
```
