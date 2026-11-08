Subfleet and Aircraft Expenses Being Applied to Wrong Airline
Subfleet and Aircraft based expenses are being applied to all airlines, even to airlines without subfleets/aircraft.

**Version**
7.0.0-dev+231215.655f15

**To Reproduce**
Steps to reproduce the behavior:
1. Go to Admin > Fleets, pick one subfleet and click edit
2. Add some daily expenses to the subfleet
3. Either wait for daily cron to run at midnight or force run it
4. Check your cron log, you will see that the expense is applied to other airlines and subfleets too (!)
5. Also check your finances, or better transactions, you will see that the expense is applied at all assets (!)

**Expected behavior**
Daily / Monthly expenses should be applied to *relevant* subfleets / aircraft, not to all.

**Additional context**
Looks like there are logical problems while picking up proper objects.

![image](https://github.com/nabeelio/phpvms/assets/74361521/33454925-9078-4cac-b20a-7f48e33598b2)

![image](https://github.com/nabeelio/phpvms/assets/74361521/3bd69341-6110-4eb7-a422-9f174e3aa5eb)

![image](https://github.com/nabeelio/phpvms/assets/74361521/9e94cd07-bc42-47ab-89b4-13416428bb38)

```
[2023-12-16 16:02:49] production.INFO: Nightly: Applying daily expenses
[2023-12-16 16:02:49] production.INFO: Charging to DSH
[2023-12-16 16:02:49] production.INFO: Charging to DSC
[2023-12-16 16:02:49] production.INFO: Charging to DSH
[2023-12-16 16:02:49] production.INFO: Expense memo: "Subfleet Expense: Daily Check"; group: "Subfleet: Daily Check" charged!
[2023-12-16 16:02:49] production.INFO: Charging to DSC
[2023-12-16 16:02:49] production.INFO: Expense memo: "Subfleet Expense: Daily Check"; group: "Subfleet: Daily Check" charged!
[2023-12-16 16:02:49] production.INFO: Nightly: Recalculating balances
```
```
[2023-12-16 16:02:59] production.INFO: Monthly: Applying monthly expenses
[2023-12-16 16:02:59] production.INFO: Charging to DSH
[2023-12-16 16:02:59] production.INFO: Charging to DSC
[2023-12-16 16:02:59] production.INFO: Charging to DSH
[2023-12-16 16:02:59] production.INFO: Expense memo: "Subfleet Expense: Leasing Payments"; group: "Subfleet: Leasing Payments" charged!
[2023-12-16 16:02:59] production.INFO: Charging to DSC
[2023-12-16 16:02:59] production.INFO: Expense memo: "Subfleet Expense: Leasing Payments"; group: "Subfleet: Leasing Payments" charged!
[2023-12-16 16:02:59] production.INFO: Charging to DSH
[2023-12-16 16:02:59] production.INFO: Expense memo: "Aircraft Expense: Aircraft Leasing Expenses (TC-DSP)"; group: "Aircraft: Aircraft Leasing Expenses (TC-DSP-TC-DSP)" charged!
[2023-12-16 16:02:59] production.INFO: Charging to DSC
[2023-12-16 16:02:59] production.INFO: Expense memo: "Aircraft Expense: Aircraft Leasing Expenses (TC-DSP)"; group: "Aircraft: Aircraft Leasing Expenses (TC-DSP-TC-DSP)" charged!
```

![image](https://github.com/nabeelio/phpvms/assets/74361521/a4435af1-a2ed-4273-b4b0-e2149d86604d)

### Additional contract requirements

- `FinanceService` must provide `addExpense(array $attrs, Model $model = null, int $airline_id = null): Expense`. It creates and persists an expense, associates the supplied model when provided, assigns the supplied airline identifier when provided, and returns the created expense.
- `RecurringFinanceService` must provide `processExpenses(string $type = ExpenseType::DAILY): void`. It processes recurring expenses only for the supplied daily or monthly frequency.
