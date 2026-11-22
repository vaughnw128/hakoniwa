#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Configure a repository to use Hakoniwa workflows.

Usage:
  scripts/configure-repo.sh --repo PATH --language rust [options]

Writes:
  .github/workflows/verify.yml           quality and tests on PRs and main
  .github/workflows/verify-pr.yml        Conventional Commit PR title and commits
  .github/workflows/security.yml         Checkov (PR comment), Semgrep, optional CodeQL, dependency age
  .github/workflows/build.yml            PR candidates (Grype-scanned) and release on merge
  .github/workflows/commands.yml         /build and /upgrade PR comment commands
  .github/workflows/pre-commit.yml       runs .pre-commit-config.yaml in CI
  .github/workflows/package-cleanup.yml  prunes old PR candidate images
  .pre-commit-config.yaml, .checkov.yaml

Options:
  --repo PATH             Target repository path. Required.
  --language NAME         python, rust, go, or none. Default: none.
  --python-version VER    Python version for CI. Default: auto from repo config.
  --binary-name NAME      Rust binary name. Required for rust.
  --helm-path PATH        Consumer chart path, for example ./helm.
  --chart-name NAME       Helm chart package name. Default: repository name.
  --cache-ref REF         BuildKit registry cache ref for image builds.
  --platforms LIST        Docker platforms. Default: linux/amd64,linux/arm64.
  --dependency-min-age-days N
                          Minimum package publish age before candidate builds. Default: 7.
  --workflow-ref REF      Hakoniwa ref to call. Default: main.
  --enable-codeql         Add an advanced CodeQL job. Leave off when CodeQL default setup is on.
  --flux-repo OWNER/NAME  Flux repo that /upgrade and releases update. Default: vaughnw128/immanent-grove.
  --flux-base BRANCH      Flux repo branch those PRs target. Default: main.
  --flux-file PATH        HelmRelease path in the Flux repo; {chart} is the chart name.
                          Default: applications/{chart}/helmrelease.yaml.
  --no-flux               Do not deploy to Flux (no /upgrade, no Flux PR on release).
  --no-pr-check           Do not write verify-pr.yml.
  --no-security           Do not write security.yml.
  --no-package-cleanup    Do not write package-cleanup.yml.
  --no-pre-commit         Do not write pre-commit.yml, .pre-commit-config.yaml or .checkov.yaml.
  --force                 Overwrite existing files.
  -h, --help              Show this help.

With Flux enabled, the repository needs the APP_ID variable and PRIVATE_KEY secret of the
GitHub App that opens Flux PRs.
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
enable_codeql=0
write_flux=1
flux_repo="vaughnw128/immanent-grove"
flux_base="main"
flux_file="applications/{chart}/helmrelease.yaml"
write_pr_check=1
write_security=1
write_package_cleanup=1
write_pre_commit=1
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
    --enable-codeql) enable_codeql=1; shift ;;
    --flux-repo) flux_repo="${2:?missing value for --flux-repo}"; shift 2 ;;
    --flux-base) flux_base="${2:?missing value for --flux-base}"; shift 2 ;;
    --flux-file) flux_file="${2:?missing value for --flux-file}"; shift 2 ;;
    --no-flux) write_flux=0; shift ;;
    --no-pr-check) write_pr_check=0; shift ;;
    --no-security) write_security=0; shift ;;
    --no-package-cleanup) write_package_cleanup=0; shift ;;
    --no-pre-commit) write_pre_commit=0; shift ;;
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

if [[ "$language" == "rust" && -z "$binary_name" ]]; then
  echo "--binary-name is required for --language rust" >&2
  exit 2
fi

if [[ ! "$dependency_min_age_days" =~ ^[0-9]+$ ]]; then
  echo "--dependency-min-age-days must be a non-negative integer" >&2
  exit 2
fi

if [[ "$write_flux" -eq 1 && -z "$helm_path" ]]; then
  write_flux=0
fi

repo="$(cd "$repo" && pwd)"
workflow_dir="$repo/.github/workflows"
hakoniwa="vaughnw128/hakoniwa/.github/workflows"
workflow_ref="${workflow_ref#@}"
templates="$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates/pre-commit" && pwd)"

yaml_line() {
  local name="$1"
  local value="$2"
  local indent="${3:-6}"
  [[ -n "$value" ]] || return 0
  printf '\n%*s%s: %s' "$indent" "" "$name" "$value"
}

write_file() {
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

copy_file() {
  local from="$1"
  local path="$2"
  if [[ -e "$path" && "$force" -ne 1 ]]; then
    echo "skip $path (exists; use --force to overwrite)"
    return 0
  fi
  cp "$from" "$path"
  echo "write $path"
}

build_inputs="      language: $language"
build_inputs+="$(yaml_line python-version "$python_version")"
build_inputs+="$(yaml_line binary-name "$binary_name")"
build_inputs+="$(yaml_line helm-path "$helm_path")"
build_inputs+="$(yaml_line chart-name "$chart_name")"
build_inputs+="$(yaml_line platforms "$platforms")"
build_inputs+="$(yaml_line cache-ref "$cache_ref")"

verify_inputs="      language: $language"
verify_inputs+="$(yaml_line python-version "$python_version")"
verify_inputs+="$(yaml_line binary-name "$binary_name")"
verify_inputs+="$(yaml_line helm-path "$helm_path")"

codeql_languages=""
if [[ "$enable_codeql" -eq 1 ]]; then
  case "$language" in
    python) codeql_languages='["python"]' ;;
    go) codeql_languages='["go"]' ;;
    rust) codeql_languages='["rust"]' ;;
  esac
fi

failure_job() {
  cat <<EOF

  notify-failure:
    needs: $1
    if: \${{ always() && github.event_name == 'pull_request' && needs.$1.result == 'failure' }}
    permissions:
      actions: read
      contents: read
      issues: write
    uses: $hakoniwa/pr-failure-comment.yml@$workflow_ref
    with:
      pr-number: \${{ github.event.pull_request.number }}
      title: "$2"
EOF
}

# --- verify.yml -------------------------------------------------------------
write_file "$workflow_dir/verify.yml" "$(cat <<EOF
name: Verify

on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: verify-\${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: \${{ github.event_name == 'pull_request' }}

permissions: {}

jobs:
  verify:
    permissions:
      contents: read
      packages: read
    uses: $hakoniwa/verify.yml@$workflow_ref
    with:
$verify_inputs
$(failure_job verify "Verify failed.")
EOF
)"

# --- verify-pr.yml ----------------------------------------------------------
if [[ "$write_pr_check" -eq 1 ]]; then
  write_file "$workflow_dir/verify-pr.yml" "$(cat <<EOF
name: Verify PR

on:
  pull_request:
    types: [opened, edited, synchronize, reopened, ready_for_review]

concurrency:
  group: verify-pr-\${{ github.event.pull_request.number }}
  cancel-in-progress: true

permissions: {}

jobs:
  verify-pr:
    permissions:
      contents: read
    uses: $hakoniwa/verify-pr.yml@$workflow_ref
    with:
      pr-title: \${{ github.event.pull_request.title }}
      pr-body: \${{ github.event.pull_request.body || '' }}
$(failure_job verify-pr "PR metadata check failed.")
EOF
)"
fi

# --- security.yml -----------------------------------------------------------
if [[ "$write_security" -eq 1 ]]; then
  security_inputs="      language: $language"
  if [[ -n "$codeql_languages" ]]; then
    security_inputs+="$(yaml_line codeql-languages "'$codeql_languages'")"
  fi
  security_inputs+="$(yaml_line dependency-min-age-days "$dependency_min_age_days")"
  write_file "$workflow_dir/security.yml" "$(cat <<EOF
name: Security

on:
  pull_request:
  push:
    branches: [main]
  schedule:
    - cron: "0 8 * * 1"

concurrency:
  group: security-\${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: \${{ github.event_name == 'pull_request' }}

permissions: {}

jobs:
  scan:
    permissions:
      contents: read
      actions: read
      pull-requests: write
      security-events: write
    uses: $hakoniwa/code-scanning.yml@$workflow_ref
    with:
$security_inputs
    secrets:
      SEMGREP_APP_TOKEN: \${{ secrets.SEMGREP_APP_TOKEN }}
$(failure_job scan "Security checks failed.")
EOF
)"
fi

# --- build.yml --------------------------------------------------------------
if [[ "$write_flux" -eq 1 ]]; then
  flux_release="
      flux-repo: $flux_repo
      flux-base: $flux_base
      flux-file: $flux_file
      app-id: \${{ vars.APP_ID }}
    secrets:
      APP_PRIVATE_KEY: \${{ secrets.PRIVATE_KEY }}"
else
  flux_release="
      flux-repo: \"\""
fi

write_file "$workflow_dir/build.yml" "$(cat <<EOF
name: Build

on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
  push:
    branches: [main]
  workflow_dispatch:

concurrency:
  group: build-\${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: \${{ github.event_name == 'pull_request' }}

permissions: {}

jobs:
  candidate:
    if: \${{ github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository && !github.event.pull_request.draft }}
    permissions:
      contents: read
      checks: read
      packages: write
      security-events: write
    uses: $hakoniwa/candidate.yml@$workflow_ref
    with:
      ref: \${{ github.event.pull_request.head.sha }}
      candidate-kind: pr
      candidate-id: \${{ github.event.pull_request.number }}
$build_inputs
      dependency-min-age-days: $dependency_min_age_days
      image-scan-fail-build: true
      image-scan-severity-cutoff: critical
      image-scan-only-fixed: true

  candidate-comment:
    needs: candidate
    if: \${{ needs.candidate.result == 'success' }}
    permissions:
      contents: read
      pull-requests: write
    uses: $hakoniwa/pr-candidate-comment.yml@$workflow_ref
    with:
      pr-number: \${{ github.event.pull_request.number }}
      head-sha: \${{ github.event.pull_request.head.sha }}
      image: \${{ needs.candidate.outputs.image }}
      digest: \${{ needs.candidate.outputs.digest }}
      chart-url: \${{ needs.candidate.outputs.chart_url }}
      chart-version: \${{ needs.candidate.outputs.chart_version }}$(yaml_line chart-name "$chart_name")

  release:
    if: \${{ github.event_name != 'pull_request' && !contains(github.event.head_commit.message || '', '[skip release]') }}
    permissions:
      contents: write
      checks: read
      packages: write
      pull-requests: read
      issues: read
      security-events: write
    uses: $hakoniwa/release-on-merge.yml@$workflow_ref
    with:
$build_inputs$flux_release
EOF
)"

# --- commands.yml -----------------------------------------------------------
upgrade_job=""
if [[ "$write_flux" -eq 1 ]]; then
  upgrade_job="$(cat <<EOF

  upgrade:
    if: \${{ github.event.issue.pull_request && github.event.comment.user.type != 'Bot' && startsWith(github.event.comment.body, '/upgrade') }}
    permissions:
      contents: read
      pull-requests: write
      issues: write
    uses: $hakoniwa/pr-upgrade-command.yml@$workflow_ref
    with:
      issue-number: \${{ github.event.issue.number }}
      comment-body: \${{ github.event.comment.body }}
      flux-repo: $flux_repo
      flux-base: $flux_base
      flux-file: $flux_file
      app-id: \${{ vars.APP_ID }}
    secrets:
      APP_PRIVATE_KEY: \${{ secrets.PRIVATE_KEY }}
EOF
)"
fi

write_file "$workflow_dir/commands.yml" "$(cat <<EOF
name: Commands

on:
  issue_comment:
    types: [created]

concurrency:
  group: commands-\${{ github.event.issue.number }}-\${{ github.event.comment.id }}
  cancel-in-progress: false

permissions: {}

jobs:
  build:
    if: \${{ github.event.issue.pull_request && github.event.comment.user.type != 'Bot' && startsWith(github.event.comment.body, '/build') }}
    permissions:
      contents: read
      actions: write
      pull-requests: read
      issues: write
    uses: $hakoniwa/pr-build-command.yml@$workflow_ref
    with:
      issue-number: \${{ github.event.issue.number }}
$upgrade_job
EOF
)"

# --- pre-commit -------------------------------------------------------------
if [[ "$write_pre_commit" -eq 1 ]]; then
  write_file "$workflow_dir/pre-commit.yml" "$(cat <<EOF
name: Pre-commit

on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: pre-commit-\${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: \${{ github.event_name == 'pull_request' }}

permissions: {}

jobs:
  pre-commit:
    permissions:
      contents: read
    uses: $hakoniwa/pre-commit.yml@$workflow_ref
    with:
      language: $language$(yaml_line python-version "$python_version")
EOF
)"

  config="$(cat "$templates/base.yaml")"
  if [[ -f "$templates/$language.yaml" ]]; then
    config+=$'\n\n'"$(cat "$templates/$language.yaml")"
  fi
  write_file "$repo/.pre-commit-config.yaml" "$config"
  copy_file "$templates/checkov.yaml" "$repo/.checkov.yaml"
fi

# --- package-cleanup.yml ----------------------------------------------------
if [[ "$write_package_cleanup" -eq 1 ]]; then
  write_file "$workflow_dir/package-cleanup.yml" "$(cat <<EOF
name: Package Cleanup

on:
  schedule:
    - cron: "23 6 * * 0"
  workflow_dispatch:

permissions: {}

jobs:
  cleanup:
    permissions:
      contents: read
      packages: write
    uses: $hakoniwa/package-cleanup.yml@$workflow_ref
    with:
      package-name: \${{ github.event.repository.name }}
      retention-days: 14
      tag-prefixes: pr-
      exact-tags: buildcache
      min-versions-to-keep: 5
      dry-run: false
EOF
)"
fi

echo
echo "configured Hakoniwa workflows in $workflow_dir"
echo "next: review the files, run 'pre-commit install', and delete any old per-repo Renovate workflow"
