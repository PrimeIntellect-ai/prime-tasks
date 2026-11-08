An alias is set in the GROUP BY when a CASE term is used, which is invalid
A fix for the use of alias' in GROUP BY clauses was previously added in https://github.com/kayak/pypika/pull/42.

However, this fix was only added to the Function class.

If a CASE statement is being used in the GROUP BY clause, then this needs to stop adding the alias after the CASE 'END' in the GROUP BY clause, as this is invalid SQL.
