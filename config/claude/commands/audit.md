Audit a complete infrastructure repository (e.g. an `infra` repo holding
Terraform, Ansible, Kubernetes/Helm, Docker, CI/CD and runner configuration).
Be thorough but report only actionable findings.

First, get oriented: detect which stacks are present (look for `*.tf`,
`playbook*.yml` / `roles/`, `*.yaml` k8s manifests, `Chart.yaml`,
`Dockerfile` / `compose*.yml`, `.github/workflows/`) and state what you found
before diving in.

Then audit each stack that applies:

1. **Terraform / OpenTofu**: provider & module version pinning, remote state
   backend + locking, hardcoded secrets/credentials, overly permissive IAM /
   security groups / firewall rules, `count`/`for_each` footguns, missing
   `prevent_destroy` on stateful resources, drift (`terraform plan` if safe).
2. **Ansible**: idempotency, `become` scope, secrets in plaintext vs Vault,
   pinned collection/role versions, `shell`/`command` where a module exists.
3. **Kubernetes / Helm**: resource requests & limits, liveness/readiness
   probes, `latest` image tags, `securityContext` (runAsNonRoot, readOnlyRootFS,
   dropped capabilities), NetworkPolicies, secrets as plaintext vs sealed/SOPS,
   RBAC scope, pinned chart/dependency versions.
4. **Docker**: pinned base images (digest), non-root USER, layer/secret leakage,
   `.dockerignore`, multi-stage build hygiene.
5. **CI/CD & runners**: actions pinned to SHA not floating tags, least-privilege
   `permissions:`, secret handling, `runs-on` correctness, self-hosted / ARC
   runner labels matching what workflows request, no secrets exposed to
   untrusted PRs (`pull_request_target`).
6. **Secrets & supply chain**: anything committed that shouldn't be, `.gitignore`
   / gitleaks coverage, unpinned or unmaintained dependencies.

For each finding report:
- **Severity** (🔴 critical / 🟡 warning / 🟢 nit)
- **Location** (file:line)
- **Why it matters**
- **Suggested fix** (concrete command or diff)

Prefer read-only inspection. Do NOT apply changes, run `terraform apply`,
install anything, or run destructive commands. If a check needs cloud/cluster
credentials, say so rather than attempting it. End with a prioritized summary
grouped by severity.
