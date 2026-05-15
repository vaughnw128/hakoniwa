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
  --python-version VER    Python version for CI. Default: auto from repo config.
  --binary-name NAME      Rust binary name.
  --helm-path PATH        Consumer chart path, for example ./helm.
  --chart-name NAME       Helm chart package name.
  --cache-ref REF         BuildKit registry cache ref for image builds.
  --platforms LIST        Docker platforms. Default: linux/amd64,linux/arm64.
  --dependency-min-age-days N
                         Minimum package publish age before candidate builds. Default: 7.
  --workflow-ref REF      Hakoniwa ref to use. Default: main.
  --preview-command TEXT  Preview command. Default: euclid build.
  --release-command TEXT  Release command prefix. Default: euclid release.
  --merge-method METHOD   merge, squash, or rebase. Default: squash.
  --required-approvals N  Current approving reviews required for release. Default: 1.
  --allowed-author-associations LIST
                         Comment author associations allowed to run commands. Default: OWNER,MEMBER.
  --enable-codeql         Generate an advanced CodeQL job. Leave off when GitHub CodeQL default setup is enabled.
  --no-pr-check           Do not write verify-pr.yml.
  --no-security           Do not write security.yml.
  --no-help               Do not write pr-help.yml.
  --no-preview            Do not write pr-candidate.yml.
  --no-release            Do not write pr-release.yml.
  --no-package-cleanup    Do not write package-cleanup.yml.
  --force                 Overwrite existing workflow files.
  -h, --help              Show this help.
USAGE
}

repo=""
language="none"
python_version=""
binary_name=""
helm_path=""
chart_name=""
cache_ref=""
platforms="linux/amd64,linux/arm64"
dependency_min_age_days="7"
workflow_ref="main"
preview_command="euclid build"
release_command="euclid release"
merge_method="squash"
required_approvals="1"
allowed_author_associations="OWNER,MEMBER"
enable_codeql=0
write_help=1
write_preview=1
write_release=1
write_package_cleanup=1
write_pr_check=1
write_security=1
force=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="${2:?missing value for --repo}"; shift 2 ;;
    --language) language="${2:?missing value for --language}"; shift 2 ;;
    --python-version) python_version="${2:?missing value for --python-version}"; shift 2 ;;
    --binary-name) binary_name="${2:?missing value for --binary-name}"; shift 2 ;;
    --helm-path) helm_path="${2:?missing value for --helm-path}"; shift 2 ;;
    --chart-name) chart_name="${2:?missing value for --chart-name}"; shift 2 ;;
    --cache-ref) cache_ref="${2:?missing value for --cache-ref}"; shift 2 ;;
    --platforms) platforms="${2:?missing value for --platforms}"; shift 2 ;;
    --dependency-min-age-days) dependency_min_age_days="${2:?missing value for --dependency-min-age-days}"; shift 2 ;;
    --workflow-ref) workflow_ref="${2:?missing value for --workflow-ref}"; shift 2 ;;
    --preview-command) preview_command="${2:?missing value for --preview-command}"; shift 2 ;;
    --release-command) release_command="${2:?missing value for --release-command}"; shift 2 ;;
    --merge-method) merge_method="${2:?missing value for --merge-method}"; shift 2 ;;
    --required-approvals) required_approvals="${2:?missing value for --required-approvals}"; shift 2 ;;
    --allowed-author-associations) allowed_author_associations="${2:?missing value for --allowed-author-associations}"; shift 2 ;;
    --enable-codeql) enable_codeql=1; shift ;;
    --no-pr-check) write_pr_check=0; shift ;;
    --no-security) write_security=0; shift ;;
    --no-help) write_help=0; shift ;;
    --no-preview) write_preview=0; shift ;;
    --no-release) write_release=0; shift ;;
    --no-package-cleanup) write_package_cleanup=0; shift ;;
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

if [[ ! "$required_approvals" =~ ^[0-9]+$ ]]; then
  echo "--required-approvals must be a non-negative integer" >&2
  exit 2
fi

if [[ ! "$dependency_min_age_days" =~ ^[0-9]+$ ]]; then
  echo "--dependency-min-age-days must be a non-negative integer" >&2
  exit 2
fi

if [[ -z "$allowed_author_associations" ]]; then
  echo "--allowed-author-associations must not be empty" >&2
  exit 2
fi

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

python_line="$(yaml_line "python-version" "$python_version")"
binary_line="$(yaml_line "binary-name" "$binary_name")"
helm_line="$(yaml_line "helm-path" "$helm_path")"
chart_line="$(yaml_line "chart-name" "$chart_name")"
cache_line="$(yaml_line "cache-ref" "$cache_ref")"
platforms_line="$(yaml_line "platforms" "$platforms")"
dependency_age_line="$(yaml_line "dependency-min-age-days" "$dependency_min_age_days")"
codeql_languages=""
if [[ "$enable_codeql" -eq 1 ]]; then
  case "$language" in
    python) codeql_languages='["python"]' ;;
    go) codeql_languages='["go"]' ;;
    *) codeql_languages="" ;;
  esac
fi
codeql_line=""
if [[ -n "$codeql_languages" ]]; then
  codeql_line="$(yaml_line "codeql-languages" "'$codeql_languages'")"
fi

verify=$(cat <<EOF
name: Verify

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read
  actions: read
  issues: write
  packages: read

jobs:
  verify:
    uses: $hakoniwa/verify.yml@$workflow_ref
    with:
      language: $language
$python_line$binary_line$helm_line
    secrets: inherit

  notify-failure:
    needs: verify
    if: \${{ always() && github.event_name == 'pull_request' && needs.verify.result != 'success' }}
    permissions:
      actions: read
      contents: read
      issues: write
    uses: $hakoniwa/pr-failure-comment.yml@$workflow_ref
    with:
      pr-number: \${{ github.event.pull_request.number }}
      title: "Verify failed."
EOF
)
write_workflow "$workflow_dir/verify.yml" "$verify"

if [[ "$write_pr_check" -eq 1 ]]; then
  pr_check=$(cat <<EOF
name: Verify PR

on:
  pull_request:
    types: [opened, edited, synchronize, reopened, ready_for_review]

permissions:
  contents: read
  actions: read
  issues: write

jobs:
  verify-pr:
    uses: $hakoniwa/verify-pr.yml@$workflow_ref
    with:
      pr-title: \${{ github.event.pull_request.title }}
      pr-body: \${{ github.event.pull_request.body || '' }}

  notify-failure:
    needs: verify-pr
    if: \${{ always() && needs.verify-pr.result != 'success' }}
    permissions:
      actions: read
      contents: read
      issues: write
    uses: $hakoniwa/pr-failure-comment.yml@$workflow_ref
    with:
      pr-number: \${{ github.event.pull_request.number }}
      title: "PR metadata check failed."
EOF
)
  write_workflow "$workflow_dir/verify-pr.yml" "$pr_check"
fi

if [[ "$write_security" -eq 1 ]]; then
  security=$(cat <<EOF
name: Security

on:
  pull_request:
  push:
    branches: [main]
  schedule:
    - cron: "0 8 * * 1"

permissions:
  contents: read
  actions: read
  issues: write
  security-events: write

jobs:
  scan:
    permissions:
      contents: read
      security-events: write
      actions: read
    uses: $hakoniwa/code-scanning.yml@$workflow_ref
    with:
      language: $language
$codeql_line
$dependency_age_line
    secrets: inherit

  notify-failure:
    needs: scan
    if: \${{ always() && github.event_name == 'pull_request' && needs.scan.result != 'success' }}
    permissions:
      actions: read
      contents: read
      issues: write
    uses: $hakoniwa/pr-failure-comment.yml@$workflow_ref
    with:
      pr-number: \${{ github.event.pull_request.number }}
      title: "Security checks failed."
EOF
)
  write_workflow "$workflow_dir/security.yml" "$security"
fi

if [[ "$write_help" -eq 1 ]]; then
  help_workflow=$(cat <<EOF
name: PR Help

on:
  pull_request:
    types: [opened, reopened, ready_for_review]

permissions:
  contents: read

jobs:
  help:
    permissions:
      contents: read
      issues: write
      pull-requests: read
    uses: $hakoniwa/pr-help.yml@$workflow_ref
    with:
      pr-number: \${{ github.event.pull_request.number }}
      preview-command: $preview_command
      release-command: $release_command
      required-approvals: "$required_approvals"
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

jobs:
  candidate:
    if: \${{ github.event.issue.pull_request && github.event.comment.user.type != 'Bot' }}
    permissions:
      actions: read
      contents: read
      issues: write
      checks: write
      packages: write
      pull-requests: read
      security-events: write
    uses: $hakoniwa/pr-candidate-command.yml@$workflow_ref
    with:
      issue-number: \${{ github.event.issue.number }}
      comment-body: \${{ github.event.comment.body || '' }}
      comment-author-association: \${{ github.event.comment.author_association || '' }}
      comment-author-type: \${{ github.event.comment.user.type || '' }}
      command-prefix: $preview_command
      allow-forks: false
      allowed-author-associations: "$allowed_author_associations"
      language: $language
$python_line$binary_line$helm_line$chart_line
$platforms_line
$cache_line
$dependency_age_line
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
  contents: read

jobs:
  release:
    if: \${{ github.event.issue.pull_request && github.event.comment.user.type != 'Bot' }}
    permissions:
      contents: write
      pull-requests: write
      issues: write
      packages: write
      checks: write
      actions: read
      security-events: write
    uses: $hakoniwa/release-command.yml@$workflow_ref
    with:
      issue-number: \${{ github.event.issue.number }}
      comment-body: \${{ github.event.comment.body || '' }}
      comment-author-association: \${{ github.event.comment.author_association || '' }}
      comment-author-type: \${{ github.event.comment.user.type || '' }}
      command-prefix: $release_command
      allowed-author-associations: "$allowed_author_associations"
      language: $language
$python_line$binary_line$helm_line$chart_line
$platforms_line
$cache_line
      merge-method: $merge_method
      required-approvals: "$required_approvals"
    secrets: inherit
EOF
)
  write_workflow "$workflow_dir/pr-release.yml" "$release"
fi

if [[ "$write_package_cleanup" -eq 1 ]]; then
  package_cleanup=$(cat <<EOF
name: Package Cleanup

on:
  schedule:
    - cron: "23 6 * * 0"
  workflow_dispatch:

permissions:
  contents: read
  packages: write

jobs:
  cleanup:
    uses: $hakoniwa/package-cleanup.yml@$workflow_ref
    with:
      package-name: \${{ github.event.repository.name }}
      retention-days: 14
      tag-prefixes: pr-
      exact-tags: buildcache
      min-versions-to-keep: 5
      dry-run: false
EOF
)
  write_workflow "$workflow_dir/package-cleanup.yml" "$package_cleanup"
fi

echo
echo "configured Hakoniwa workflows in $workflow_dir"
echo "next: review generated files, then run actionlint in the target repo"
