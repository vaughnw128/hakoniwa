#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Configure a repository to use Hakoniwa workflows.

Usage:
  scripts/configure-repo.sh --repo PATH --language rust [options]

Options:
  --repo PATH             Target repository path. Required.
  --language NAME         python, rust, go, or none. Default: none.
  --binary-name NAME      Rust binary name.
  --helm-path PATH        Consumer chart path, for example ./helm.
  --chart-name NAME       Helm chart package name.
  --cache-ref REF         BuildKit registry cache ref for image builds.
  --workflow-ref REF      Hakoniwa ref to use. Default: main.
  --preview-command TEXT  Preview command. Default: euclid build.
  --release-command TEXT  Release command prefix. Default: euclid release.
  --merge-method METHOD   merge, squash, or rebase. Default: squash.
  --no-pr-check           Do not write verify-pr.yml.
  --no-help               Do not write pr-help.yml.
  --no-preview            Do not write pr-candidate.yml.
  --no-release            Do not write pr-release.yml.
  --force                 Overwrite existing workflow files.
  -h, --help              Show this help.
USAGE
}

repo=""
language="none"
binary_name=""
helm_path=""
chart_name=""
cache_ref=""
workflow_ref="main"
preview_command="euclid build"
release_command="euclid release"
merge_method="squash"
write_help=1
write_preview=1
write_release=1
write_pr_check=1
force=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="${2:?missing value for --repo}"; shift 2 ;;
    --language) language="${2:?missing value for --language}"; shift 2 ;;
    --binary-name) binary_name="${2:?missing value for --binary-name}"; shift 2 ;;
    --helm-path) helm_path="${2:?missing value for --helm-path}"; shift 2 ;;
    --chart-name) chart_name="${2:?missing value for --chart-name}"; shift 2 ;;
    --cache-ref) cache_ref="${2:?missing value for --cache-ref}"; shift 2 ;;
    --workflow-ref) workflow_ref="${2:?missing value for --workflow-ref}"; shift 2 ;;
    --preview-command) preview_command="${2:?missing value for --preview-command}"; shift 2 ;;
    --release-command) release_command="${2:?missing value for --release-command}"; shift 2 ;;
    --merge-method) merge_method="${2:?missing value for --merge-method}"; shift 2 ;;
    --no-pr-check) write_pr_check=0; shift ;;
    --no-help) write_help=0; shift ;;
    --no-preview) write_preview=0; shift ;;
    --no-release) write_release=0; shift ;;
    --force) force=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$repo" ]]; then
  echo "--repo is required" >&2
  usage >&2
  exit 2
fi

case "$language" in
  python|rust|go|none) ;;
  *) echo "--language must be python, rust, go, or none" >&2; exit 2 ;;
esac

case "$merge_method" in
  merge|squash|rebase) ;;
  *) echo "--merge-method must be merge, squash, or rebase" >&2; exit 2 ;;
esac

repo="$(cd "$repo" && pwd)"
workflow_dir="$repo/.github/workflows"
hakoniwa="vaughnw128/hakoniwa/.github/workflows"
workflow_ref="${workflow_ref#@}"

yaml_line() {
  local name="$1"
  local value="$2"
  local indent="${3:-6}"
  [[ -n "$value" ]] || return 0
  printf '\n%*s%s: %s' "$indent" "" "$name" "$value"
}

write_workflow() {
  local path="$1"
  local content="$2"

  mkdir -p "$(dirname "$path")"
  if [[ -e "$path" && "$force" -ne 1 ]]; then
    echo "skip $path (exists; use --force to overwrite)"
    return 0
  fi

  printf '%s\n' "$content" > "$path"
  echo "write $path"
}

binary_line="$(yaml_line "binary-name" "$binary_name")"
helm_line="$(yaml_line "helm-path" "$helm_path")"
chart_line="$(yaml_line "chart-name" "$chart_name")"
cache_line="$(yaml_line "cache-ref" "$cache_ref")"

verify=$(cat <<EOF
name: Verify

on:
  pull_request:
  push:
    branches: [main]

jobs:
  verify:
    uses: $hakoniwa/verify.yml@$workflow_ref
    with:
      language: $language
$binary_line$helm_line
    secrets: inherit
EOF
)
write_workflow "$workflow_dir/verify.yml" "$verify"

if [[ "$write_pr_check" -eq 1 ]]; then
  pr_check=$(cat <<EOF
name: Verify PR

on:
  pull_request:
    types: [opened, edited, synchronize, reopened, ready_for_review]

jobs:
  verify-pr:
    uses: $hakoniwa/verify-pr.yml@$workflow_ref
    with:
      pr-title: \${{ github.event.pull_request.title }}
      pr-body: \${{ github.event.pull_request.body || '' }}
EOF
)
  write_workflow "$workflow_dir/verify-pr.yml" "$pr_check"
fi

if [[ "$write_help" -eq 1 ]]; then
  help_workflow=$(cat <<EOF
name: PR Help

on:
  pull_request:
    types: [opened, reopened, ready_for_review]

permissions:
  contents: read
  issues: write
  pull-requests: read

jobs:
  help:
    uses: $hakoniwa/pr-help.yml@$workflow_ref
    with:
      pr-number: \${{ github.event.pull_request.number }}
      preview-command: $preview_command
      release-command: $release_command
    secrets: inherit
EOF
)
  write_workflow "$workflow_dir/pr-help.yml" "$help_workflow"
fi

if [[ "$write_preview" -eq 1 ]]; then
  preview=$(cat <<EOF
name: PR Candidate

on:
  issue_comment:
    types: [created]

concurrency:
  group: \${{ startsWith(github.event.comment.body || '', '$preview_command') && format('candidate-{0}', github.event.issue.number) || format('issue-comment-{0}-{1}', github.event.issue.number, github.run_id) }}
  cancel-in-progress: true

permissions:
  contents: read
  issues: write
  packages: write
  pull-requests: read

jobs:
  prepare:
    if: \${{ github.event.issue.pull_request }}
    uses: $hakoniwa/pr-comment-prepare.yml@$workflow_ref
    with:
      issue-number: \${{ github.event.issue.number }}
      comment-body: \${{ github.event.comment.body || '' }}
      comment-author-association: \${{ github.event.comment.author_association || '' }}
      command-prefix: $preview_command
      allow-forks: false
    secrets: inherit

  candidate:
    needs: prepare
    if: \${{ needs.prepare.outputs.should_run == 'true' }}
    uses: $hakoniwa/candidate.yml@$workflow_ref
    with:
      ref: \${{ needs.prepare.outputs.head_sha }}
      candidate-kind: pr
      candidate-id: \${{ needs.prepare.outputs.pr_number }}
      language: $language
$binary_line$helm_line$chart_line
$cache_line
    secrets: inherit
EOF
)
  write_workflow "$workflow_dir/pr-candidate.yml" "$preview"
fi

if [[ "$write_release" -eq 1 ]]; then
  release=$(cat <<EOF
name: PR Release

on:
  issue_comment:
    types: [created]

concurrency:
  group: \${{ startsWith(github.event.comment.body || '', '$release_command') && format('release-{0}', github.event.issue.number) || format('issue-comment-{0}-{1}', github.event.issue.number, github.run_id) }}
  cancel-in-progress: false

permissions:
  contents: write
  pull-requests: write
  issues: write
  packages: write
  checks: read
  actions: read

jobs:
  release:
    if: \${{ github.event.issue.pull_request }}
    uses: $hakoniwa/release-command.yml@$workflow_ref
    with:
      issue-number: \${{ github.event.issue.number }}
      comment-body: \${{ github.event.comment.body || '' }}
      comment-author-association: \${{ github.event.comment.author_association || '' }}
      command-prefix: $release_command
      language: $language
$binary_line$helm_line$chart_line
$cache_line
      merge-method: $merge_method
      require-approval: true
    secrets: inherit
EOF
)
  write_workflow "$workflow_dir/pr-release.yml" "$release"
fi

echo
echo "configured Hakoniwa workflows in $workflow_dir"
echo "next: review generated files, then run actionlint in the target repo"
