

# hakoniwa

A boxed garden for optimal CI/CD cultivation.

![katamari](katamari.gif)

## Reusable Workflows

Reference as `vaughnw128/hakoniwa/.github/workflows/<name>@main`.

### Test + build + bump (Python)

```yaml
# test.yml
jobs:
  test:
    uses: vaughnw128/hakoniwa/.github/workflows/test.yml@main
    with:
      language: python
      helm-path: ./charts/single-container

# build.yml - triggered by test workflow completion
jobs:
  build:
    uses: vaughnw128/hakoniwa/.github/workflows/build-and-release.yml@main
    secrets: inherit

  bump:
    needs: build
    uses: vaughnw128/hakoniwa/.github/workflows/bump.yml@main
    with:
      new_version: ${{ needs.build.outputs.new_version }}
      language: python
    secrets: inherit
```

### Rust app with binaries

```yaml
jobs:
  build:
    uses: vaughnw128/hakoniwa/.github/workflows/build-and-release.yml@main
    secrets: inherit

  binaries:
    needs: build
    uses: vaughnw128/hakoniwa/.github/workflows/release-binaries.yml@main
    with:
      new_version: ${{ needs.build.outputs.new_version }}
      binary-name: my-app
    secrets: inherit

  bump:
    needs: build
    uses: vaughnw128/hakoniwa/.github/workflows/bump.yml@main
    with:
      new_version: ${{ needs.build.outputs.new_version }}
      language: rust
    secrets: inherit
```

### Code scanning

```yaml
jobs:
  scan:
    uses: vaughnw128/hakoniwa/.github/workflows/code-scanning.yml@main
    with:
      language: python
      codeql-languages: '["python"]'
    secrets: inherit
```

Runs CodeQL, Semgrep, Checkov IaC scan, and dependency review (PRs only). All results upload to GitHub Security.

## Helm Chart

### As OCI dependency

```yaml
# Chart.yaml
dependencies:
  - name: single-container
    version: "1.x.x"
    repository: "oci://ghcr.io/vaughnw128/charts"
```

### Example values

```yaml
name: "discsync"
image: "ghcr.io/vaughnw128/discsync"
containerPort: 8080

gateway:
  type: gateway-api-shared
  hostname: discsync.internal.vw-ops.net
  parentGatewayName: default-gateway
  parentGatewayNamespace: default
  sectionName: https
  httpsRedirect: true

db:
  enabled: true
  secretName: "sbux-oracle-pg-app"
  uriKey: "uri-pooler-rw"

secretVars:
  DISCORD_TOKEN: "discsync/discord-token"

livenessProbe:
  httpGet:
    path: /health
```

## Shared Configs

**Renovate** - reference the preset in `.renovaterc.json5`:
```json5
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["github>vaughnw128/hakoniwa:configs/renovate-preset"]
}
```

**Semantic release** - copy `configs/.releaserc.json` to your repo root.
