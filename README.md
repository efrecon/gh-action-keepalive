# Keepalived Workflows

Workflows will be automatically disabled by GitHub after 60 days of [inactivity]
on the default branch. This action keeps workflows in your repository active by
automatically generating git activity before the 60 days deadline. The action is
meant to be run from time to time using a [schedule] event. If no authorship
activity has happened for the past 41 days, the action will generate a commit
onto the default branch, through writing a date-based marker into a hidden file
within the `.github` directory. File path, inactivity period, and other
parameters can easily be controlled through input parameters, or environment
variables (for lesser used one).

This action is useful, for example, when a project needs to follow the release
tempo of another (external) project or needs to update badges from time to time.

  [inactivity]: https://docs.github.com/en/actions/managing-workflow-runs/disabling-and-enabling-a-workflow
  [schedule]: https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#schedule

## Usage

In most cases, you simply have to arrange for creating a workflow that will run
at regular intervals, e.g. once a week, and run this action as in the following
basic example.

```yaml
name: keepalive

on:
  schedule:
    # Run every sunday at 1:27 UTC
    - cron: '27 1 * * SUN'

jobs:
  keepalive:
    runs-on: ubuntu-latest
    steps:
      - name: keepalive
        uses: efrecon/gh-action-keepalive@main
```

You can also run the action as an extra step in a workflow that would already be
running from time to time, the period being less important as long as it is long
enough to be triggered before the 60 days deadline.

This action has good defaults, consult the file [action.yml](./action.yml) for a
complete list of input parameters and their usage. In addition to the API that
it provides through the different available parameters, it is also possible to
fine tune the behaviour of this action through a set of environment variables.
All variables start with the `ACTIVITY_` prefix. The value of input parameters
always have precedence over the content of the variables. Available variables
are listed, together with a brief explanation at the beginning of the main
implementation [script](./activity.sh).

## History

This implementation is the **second** attempt at keeping alive workflows over
longer period of time. A previous version was toggling twice the activity state
of all workflows. But this strategy turned out not being able to bypass GitHub's
deadline.
