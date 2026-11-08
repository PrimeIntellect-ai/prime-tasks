print(bot) should show which enemies are noisy
This will hopefully avoid confusion.

One remark: since we got rid of set_initial in the new-style API, the teams never see their enemies sitting unnoised on their initial positions, which has been a nice (and easy) starting point for filtering. Question: Do we want to be explicit about how the initial positions are fixed (ie. add an example) or do we want them to figure it out themselves?
