#!/usr/bin/env bash
# Approves a release waiting in the `release` environment: scripts/approve.sh
# (or `just approve`). The same as Review deployments -> Approve and deploy on
# the run's page: it shows the run's jobs, asks, then approves through the
# GitHub API. Only a required reviewer of the environment can approve.
# Needs gh, logged in as that reviewer.
set -euo pipefail

repo=agentux-os/agentux-os
run="$(gh run list -R "$repo" --workflow release.yml --status waiting -L 1 \
    --json databaseId --jq '.[0].databaseId // empty')"
if [[ -z $run ]]; then
    echo "No release run is waiting for approval." >&2
    echo "Runs: https://github.com/$repo/actions/workflows/release.yml" >&2
    exit 1
fi

env_id="$(gh api "repos/$repo/actions/runs/$run/pending_deployments" \
    --jq '[.[] | select(.environment.name == "release")][0].environment.id // empty')"
if [[ -z $env_id ]]; then
    echo "Run $run is waiting, but not on the release environment." >&2
    exit 1
fi

gh run view -R "$repo" "$run"
echo
echo "Approving promotes this tag's images to :stable and publishes its ISOs,"
echo "the GitHub release and latest.json."
read -rp "Approve run $run? [y/N] " ok
[[ $ok == [yY] ]] || { echo "not approved"; exit 1; }
gh api -X POST "repos/$repo/actions/runs/$run/pending_deployments" \
    -F "environment_ids[]=$env_id" -f state=approved \
    -f comment="Approved with scripts/approve.sh" >/dev/null
echo "Approved: https://github.com/$repo/actions/runs/$run"
