#!/usr/bin/env bash
# changed.sh DEPLOYED HEAD — whether the board Worker must be deployed again:
# prints one line, `deploy: <why>` or `skip: <why>`, for the deploy workflow
# (.github/workflows/project-board.yml). DEPLOYED is the commit the running
# Worker was deployed from (its VERSION), HEAD the commit CI just passed. Run
# from a clone holding the history of both.
#
# The range starts at the deployed commit, not at HEAD's parent: a change to
# the Worker whose own CI failed is deployed with the next green commit. When
# the two cannot be compared, the answer is `deploy`: deploying the same code
# again is harmless, leaving a change out is not.
set -euo pipefail

deployed="${1:-}"
head="${2:?usage: changed.sh DEPLOYED HEAD}"
# What a deploy ships, and the workflow that ships it.
paths=(.github/project-board .github/workflows/project-board.yml)

if ! [[ "$deployed" =~ ^[0-9a-f]{40}$ ]]; then
  echo "deploy: the deployed commit is unknown"
elif ! git cat-file -e "$deployed^{commit}" 2>/dev/null; then
  echo "deploy: the deployed commit $deployed is not in this history"
elif [ "$deployed" = "$(git rev-parse "$head^{commit}")" ]; then
  echo "skip: $deployed is already deployed"
elif git merge-base --is-ancestor "$head" "$deployed"; then
  # A CI run that ended after a later one's deploy.
  echo "skip: the deployed commit $deployed is newer than $head"
elif ! git merge-base --is-ancestor "$deployed" "$head"; then
  echo "deploy: the deployed commit $deployed is not an ancestor of $head"
elif git diff --quiet "$deployed" "$head" -- "${paths[@]}"; then
  echo "skip: the Worker did not change since $deployed"
else
  echo "deploy: the Worker changed since $deployed"
fi
