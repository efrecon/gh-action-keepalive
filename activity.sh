#!/bin/sh

# If editing from Windows. Choose LF as line-ending

set -eu

# Set this to 1 for more verbosity (on stderr)
ACTIVITY_VERBOSE=${ACTIVITY_VERBOSE:-0}

# Entrypoint of the GitHub API
ACTIVITY_GHAPI=${ACTIVITY_GHAPI:-"https://api.github.com/"}

# Personal Access Token
ACTIVITY_TOKEN=${ACTIVITY_TOKEN:-""}

# Git Branch to operate on, empty means default GitHub branch
ACTIVITY_BRANCH=${ACTIVITY_BRANCH:-""}

# Time since last commit to trigger fake activity (41 days in seconds by
# default)
ACTIVITY_TIMEOUT=${ACTIVITY_TIMEOUT:-"3542400"}

# Where workflow files are located within a repository
ACTIVITY_WORKFLOWS_PATH=${ACTIVITY_WORKFLOWS_PATH:-".github/workflows"}

# Activity marker to add/use within workflow YAML to keep track of changes
ACTIVITY_MARKER=${ACTIVITY_MARKER:-"Last GitHub activity at:"}

# This uses the comments behind the options to show the help. Not extremly
# correct, but effective and simple.
usage() {
  echo "$0 keeps alive all workflows of the checked out repository passed as argument" && \
    grep "[[:space:]].)\ #" "$0" |
    sed 's/#//' |
    sed -r 's/([a-z])\)/-\1/'
  exit "${1:-0}"
}

while getopts "t:s:m:vfh-" opt; do
  case "$opt" in
    t) # Personal access token
      ACTIVITY_TOKEN=$OPTARG;;
    m) # Time since last activity to trigger fake commit (in seconds)
      ACTIVITY_TIMEOUT=$OPTARG;;
    v) # Turn on verbosity
      ACTIVITY_VERBOSE=1;;
    h) # Print help and exit
      usage;;
    -)
      break;;
    *)
      usage 1;;
  esac
done
shift $((OPTIND-1))


_verbose() {
  if [ "$ACTIVITY_VERBOSE" = "1" ]; then
    printf %s\\n "$1" >&2
  fi
}

_warn() { printf %s\\n "$1" >&2; }
_error() { warn "$1" && exit 1; }

# curl wrapper around the GH API. This automatically inserts the authorization
# token and the path to the API
ghapi() {
  _api=$1; shift
  curl -sSL \
    -H "Authorization: token ${ACTIVITY_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "$@" \
    "${ACTIVITY_GHAPI%/}/repos/${_api}"
}


json_int_field() {
  grep -E "^\\s*\"${1}\"\\s*:" | sed -E "s/\\s*\"${1}\"\\s*:\\s*([0-9]+)\\s*,/\\1/${2:-}"
}

json_str_field() {
  grep -E "^\\s*\"${1}\"\\s*:" | sed -E "s/\\s*\"${1}\"\\s*:\\s*\"([^\"]+)\"\\s*,/\\1/${2:-}"
}

branch() {
  if [ -z "$ACTIVITY_BRANCH" ]; then
    _verbose "Detecting default branch for $1 at GitHub"
    ghapi "$1" | json_str_field "default_branch" | head -n 1
  else
    printf %s\\n "$ACTIVITY_BRANCH"
  fi
}

workflow_name() {
  grep -E '^name:' "$1" |
    sed -E \
      -e 's/^name:\s*//' \
      -e 's/^"//' \
      -e 's/"$//' \
      -e "s/^'//" \
      -e "s/'\$//"
}

workflow_path() {
  if printf %s\\n "$1" | grep -Eq '\.ya?ml$'; then
    if printf %s\\n "$1" | grep -Fq "$ACTIVITY_WORKFLOWS_PATH"; then
      printf %s\\n "$1"
    else
      printf %s/%s\\n "${ACTIVITY_WORKFLOWS_PATH%/}" "$1"
    fi
  else
    find "$ACTIVITY_WORKFLOWS_PATH" -name '*.yml' -o -name '*.yaml' | while IFS=$(printf \\n) read -r path; do
      if [ "$(workflow_name "$path")" = "$1" ]; then
        printf %s\\n "$path"
        break
      fi
    done
  fi
}

workflow_mark() {
  marker=$(printf '# %s %s\n' "$ACTIVITY_MARKER" "$(date -Iseconds)")
  if grep -Eq "^#+\\s+${ACTIVITY_MARKER}" "$1"; then
    sed -i -E -e "s/^#+\\s+${ACTIVITY_MARKER}.*/${marker}/g" "$1"
  else
    printf '%s\n' "$marker" >> "$1"
  fi
  _verbose "Marked workflow at $1 with current ISO date"
}

# Work only on a single repo
if [ "$#" -eq "0" ] || [ "$#" -gt "2" ]; then
  usage
fi

# Get workflow name
ACTIVITY_WORKFLOW=$1

# When no repository is provided, take a good guess at the current one.
if [ "$#" -eq "1" ]; then
  ACTIVITY_REPO=$(git config --get remote.origin.url | sed -e 's/^git@.*:\([[:graph:]]*\).git/\1/')
  _verbose "Defaulting to current repo: $ACTIVITY_REPO"
else
  ACTIVITY_REPO=$2
fi

# Refuse to continue when binaray dependencies missing
for dep in curl git; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    _error "This script requires $dep installed on the host"
  fi
done

# We need a way to talk to GH when no default activity branch is specified.
if [ -z "$ACTIVITY_TOKEN" ] && [ -z "$ACTIVITY_BRANCH" ]; then
  _error "No authorization token provided"
fi

# Detect default branch for repository and the one that we are at.
branch_default=$(branch "$ACTIVITY_REPO")
branch_current=$(git rev-parse --abbrev-ref HEAD)
_verbose "Default branch: $branch_default, currently on: $branch_current"

# Detect number of seconds since latest commit onto the default branch
date_activity=$(date -d "$(git log -1 --format=%cd --date=iso-strict "$branch_default")" +%s)
date_now=$(date +%s)
elapsed=$(( date_now - date_activity ))

# If too long has elapsed, generate a commit onto the workflow file that
# actually called this action.
exit_code=0
if [ "$elapsed" -gt "$ACTIVITY_TIMEOUT" ]; then
  _verbose "No activity for ${elapsed}s. (> ${ACTIVITY_TIMEOUT}s.)"

  # Change to the default branch as this is where activity detection happens at
  # github.
  if [ "$branch_current" != "$branch_default" ]; then
    git switch "$branch_default"
  fi

  # Resolve workflow id or path to its location on disk. This is the file that
  # we will be pushing a commit onto.
  ACTIVITY_WORKFLOW=$(workflow_path "$ACTIVITY_WORKFLOW")
  if [ -z "$ACTIVITY_WORKFLOW" ] || ! [ -f "$ACTIVITY_WORKFLOW" ]; then
    _warn "Cannot find workflow $1 (looked in $ACTIVITY_WORKFLOWS_PATH)"
    exit_code=1
  else
    # Add/change marker on the workflow file
    workflow_mark "$ACTIVITY_WORKFLOW"

    # Push the change to git, so to GitHub
    git add "$ACTIVITY_WORKFLOW"
    git commit -m "Forced activity to bypass GH workflows liveness toggling"
    git push
  fi

  # Change back to the branch that was current if relevant
  if [ "$branch_current" != "$branch_default" ]; then
    git switch "$branch_current"
  fi
fi

exit "$exit_code"