# Security Policy

## Supported Versions

GitNexus is developed on `main`. Security fixes are applied to the latest released minor on npm (`gitnexus`) and to the published Docker images (`Dockerfile.cli`, `Dockerfile.web`). Older minors are not back-patched.

## Reporting a Vulnerability

**Please do not open a public GitHub issue for security reports.**

Use **GitHub Private Vulnerability Reporting** for this repository:

→ https://github.com/abhigyanpatwari/GitNexus/security/advisories/new

Please include:

- A description of the issue and its potential impact
- Steps to reproduce (a minimal repro repo or commit hash if possible)
- The affected version(s) — `npm view gitnexus version`, image digest, or commit SHA
- Any suggested mitigation

### What to expect

- **Acknowledgement:** best-effort within 5 business days, subject to maintainer capacity.
- **Triage:** we will confirm whether the report is in scope, request clarifications if needed, and propose a fix timeline.
- **Disclosure:** coordinated. We will agree on a disclosure date with you before publishing an advisory.

### Scope

In scope:

- The `gitnexus` CLI and MCP server (`gitnexus/`)
- The `gitnexus-web` thin client (`gitnexus-web/`)
- The `gitnexus-shared` types package (`gitnexus-shared/`)
- The published Docker images (`Dockerfile.cli`, `Dockerfile.web`)
- GitHub Actions workflows in `.github/workflows/`

Out of scope:

- Vulnerabilities in third-party dependencies that we have no influence over (please report upstream; if a viable mitigation exists at the GitNexus layer, that's in scope).
- Issues requiring physical access to a developer machine or a compromised local environment.
- Theoretical attacks without a practical exploit against a default GitNexus deployment.

## Recommended Hardening for Forks and Self-Hosted Deployments

If you fork GitNexus or self-host it, we recommend enabling the following in your repository's **Settings → Code security and analysis**:

- **Private vulnerability reporting** — the channel described above.
- **Dependabot alerts** — alerts on advisories affecting your dependencies.
- **Dependabot security updates** — automated PRs for security patches (this repo's `.github/dependabot.yml` already covers version updates).
- **Secret scanning** and **Push protection** — blocks pushes that introduce known secret patterns. Defense-in-depth on top of the in-CI Gitleaks scan documented below.
- **Code scanning** — surfaces SARIF results from CodeQL, Trivy, Scorecard, and zizmor in one place.

### Hosted Deploys on Render

The `render.yaml` Blueprint (see the README's **Deploy to Render**) puts `gitnexus serve` on a **private service** with no public URL, and a public web service in front of it that reverse-proxies `/api/*`. What that does and does not protect:

- **The web service is public and its URL is discoverable.** `onrender.com` hostnames appear in certificate transparency logs. Treat the URL as known rather than secret.
- **The generated `GITNEXUS_SERVE_AUTH_TOKEN` is the only access control.** The proxy rejects any `/api/*` request without it with a `401` before forwarding. Rotate it by editing the environment variable on the `gitnexus-web` service and redeploying.
- **The CSRF guard is inert on this path.** The proxy strips `Origin` before forwarding, so the server's write-origin guard does nothing for proxied traffic — it passes `Origin`-less requests through by design. The token is not a second layer behind the guard.
- **Anyone holding the token can read every indexed repo's source.** These routes carry no origin guard, and the first three carry no rate limiter either: `GET /api/repos`, `GET /api/graph`, `POST /api/query`, `GET /api/file`, `GET /api/grep`. Whoever has the token can also index and delete repositories.
- **`POST /api/mcp` rides the same path.** `serve` mounts the MCP handler via `mountMCPEndpoints`, and `createStreamableHttpHandler` is called with no `authToken` — a **pre-existing** gap in `serve` itself, not something this deploy introduces. On Render it is closed only by the edge token and the private network. A `serve` bound directly to a public interface has no such cover.
- **Rate limits bound cost, not access.** They cap what a token holder can spend; they do not decide who gets in.

Do not hand the URL out as a public demo. A token holder has read access to everything the deploy has indexed.

## Automated Scans Running in CI

This repository runs the following scans automatically. Findings appear under the repository's **Security → Code scanning** tab.

| Scan | Tool | Trigger | Action on finding |
|------|------|---------|-------------------|
| Static analysis (JS/TS, Python) | [CodeQL](https://github.com/github/codeql-action) | PR, `main` push, weekly | Advisory (Security tab) |
| Dependency vulnerabilities (PR diff) | [`dependency-review-action`](https://github.com/actions/dependency-review-action) | PR | **Blocks PR** at `high+` severity |
| Secret scanning | [Gitleaks](https://github.com/gitleaks/gitleaks-action) | PR, `main` push | **Blocks PR** on default rules |
| Supply-chain posture | [OpenSSF Scorecard](https://github.com/ossf/scorecard-action) | Weekly, `main` push | Advisory (Security tab + public badge) |
| Workflow lint | [zizmor](https://github.com/woodruffw/zizmor) | PR (touching `.github/**`) | **Blocks PR** at `high+` severity |
| Container image scan | [Trivy](https://github.com/aquasecurity/trivy-action) | Weekly, `main` push | Advisory (Security tab) |

Dependency version updates are managed separately by Dependabot — see `.github/dependabot.yml`.

## Audit Log

Manual, point-in-time reviews conducted outside of the automated CI scans above. These are ad hoc audits, not a substitute for the continuous scans listed in the table above.

### 2026-07-10 18:32 UTC — commit `ce66646e7eaa11f40199a38dda90832edd1777a1`

**Scope:** Full-repository static sweep (not a diff) for reverse shells, backdoors/malicious logic, and data exfiltration — source, build scripts, CI workflows, editor/agent hook scripts (Claude/Cursor/Antigravity plugins), and package lifecycle scripts.

**Result: No indicators found.**

- **Reverse shells / RCE primitives:** Clean. All `exec`/`spawn` calls use fixed argv arrays against trusted local binaries (`git`, `npm`, `node-gyp`, `tsc`, `lsof`/`ps`/`which`, the `gitnexus` CLI); no `shell: true` with interpolated input, no `/bin/sh -i`, `/dev/tcp/`, `nc -e`, or PowerShell reverse-shell idioms. No dynamic execution of untrusted/decoded input.
- **Data exfiltration:** Clean. No telemetry/analytics SDKs. Outbound network calls are limited to disclosed, user-initiated paths (`gitnexus publish` → `api.github.com` with only `owner/repo`, gated behind a user-supplied PAT; BYO-LLM/embedding endpoints using the user's own configured keys; standard CDN loads for `marked`/`mermaid`). No code path forwards env vars, SSH keys, or `.git/config` externally.
- **Supply chain (install scripts, CI, hooks):** Clean. `postinstall`/`prepare` scripts only compile vendored native code locally. GitHub Actions third-party actions are pinned to commit SHAs; the one `pull_request_target` workflow gates on author association and checks out by SHA. Editor/agent hook scripts shell out to the local `gitnexus` CLI with fixed argv only, per their own in-code "never use `shell: true`" comment.
- **Obfuscated/hidden payloads:** Clean. No suspicious base64 blobs, hex-decode-then-execute patterns, obfuscated identifiers, or committed minified source. No rogue binaries outside expected native-module/test-fixture locations.

**Caveat:** Static sweep of GitNexus's own source and scripts; does not independently verify third-party dependency provenance/integrity (npm supply-chain compromise is a separate risk class from code authored in this repo).
