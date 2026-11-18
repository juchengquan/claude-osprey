# "Deploy and check"

Only when the owner says so, and only where the project has a *deploy* setting; without one, tell
the owner there is nothing to run.

1. From the tree the *deploy* setting names, run its deploy command.
2. Show each of its post-deploy checks, with the evidence for each: the command run and what it
   printed, or what was seen.
3. A check that fails is reported as it is, with its evidence. Rolling back is the owner's call.

A change to live DATA (a row to correct) is the owner's call each time: take a named backup first,
kept for good; change exactly the rows named; and show them after.
