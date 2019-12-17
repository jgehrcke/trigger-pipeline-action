#!/bin/bash

set -uo pipefail

if [[ -z "${BUILDKITE_API_ACCESS_TOKEN:-}" ]]; then
  echo "You must set the BUILDKITE_API_ACCESS_TOKEN environment variable (e.g. BUILDKITE_API_ACCESS_TOKEN = \"xyz\")"
  exit 1
fi

if [[ -z "${PIPELINE:-}" ]]; then
  echo "You must set the PIPELINE environment variable (e.g. PIPELINE = \"my-org/my-pipeline\")"
  exit 1
fi

ORG_SLUG=$(echo "${PIPELINE}" | cut -d'/' -f1)
PIPELINE_SLUG=$(echo "${PIPELINE}" | cut -d'/' -f2)

COMMIT="${COMMIT:-${GITHUB_SHA}}"
BRANCH="${BRANCH:-${GITHUB_REF#"refs/heads/"}}"
MESSAGE="${MESSAGE:-}"

NAME=$(jq -r ".pusher.name" "$GITHUB_EVENT_PATH")
EMAIL=$(jq -r ".pusher.email" "$GITHUB_EVENT_PATH")

# Use jq’s --arg properly escapes string values for us
JSON=$(
  jq -c -n \
    --arg COMMIT  "$COMMIT" \
    --arg BRANCH  "$BRANCH" \
    --arg MESSAGE "$MESSAGE" \
    --arg NAME    "$NAME" \
    --arg EMAIL   "$EMAIL" \
    --arg PR_NUMBER "$PR_NUMBER" \
    --arg PR_BASE_BRANCH "$PR_BASE_BRANCH" \
    --arg PR_REPO "$PR_REPO" \
    '{
      "commit": $COMMIT,
      "branch": $BRANCH,
      "message": $MESSAGE,
      "pull_request_id": $PR_NUMBER,
      "pull_request_base_branch": $PR_BASE_BRANCH,
      "pull_request_repository": $PR_REPO,
      "author": {
        "name": $NAME,
        "email": $EMAIL
      }
    }'
)

# Merge in the build environment variables, if they specified any
if [[ "${BUILD_ENV_VARS:-}" ]]; then
  if ! JSON=$(echo "$JSON" | jq -c --argjson BUILD_ENV_VARS "$BUILD_ENV_VARS" '. + {env: $BUILD_ENV_VARS}'); then
    echo ""
    echo "Error: BUILD_ENV_VARS provided invalid JSON: $BUILD_ENV_VARS"
    exit 1
  fi
fi

echo "JSON doc, to be POSTed for creating build:"
echo "${JSON}"

RESPONSE=$(
  curl \
    --fail \
    -X POST \
    -H "Authorization: Bearer ${BUILDKITE_API_ACCESS_TOKEN}" \
    "https://api.buildkite.com/v2/organizations/${ORG_SLUG}/pipelines/${PIPELINE_SLUG}/builds" \
    -d "$JSON"
)

echo "curl exit code: $?"
echo "response:"
echo "$RESPONSE"

echo ""
echo "Build created:"
echo "$RESPONSE" | jq --raw-output ".web_url"

# Save output for downstream actions
echo "${RESPONSE}" > "${HOME}/${GITHUB_ACTION}.json"

echo ""
echo "Saved build JSON to:"
echo "${HOME}/${GITHUB_ACTION}.json"
