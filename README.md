# ansible-role-authelia-docker
[![CI](https://github.com/ryclarke/ansible-role-authelia-docker/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/ryclarke/ansible-role-authelia-docker/actions/workflows/ci.yaml) [![Ansible Galaxy Import](https://github.com/ryclarke/ansible-role-authelia-docker/actions/workflows/publish.yaml/badge.svg)](https://github.com/ryclarke/ansible-role-authelia-docker/actions/workflows/publish.yaml)

An opinionated Ansible role that deploys a lean, hardened [Authelia](https://www.authelia.com) SSO stack via Docker Compose: **Authelia + lldap** (Lightweight LDAP), with an optional **Caddy** reverse proxy that builds a custom image with the DNS plugins of your choice, and optional **PostgreSQL + Redis** services.

Designed for single-instance homelab or small-business deployments. Boring, proven, minimal moving parts — every container runs as a pinned unprivileged user with `cap_drop: ALL`, `no-new-privileges`, and a read-only rootfs where possible.

## Requirements

- Ansible 2.15+
- Linux-based target with Python 3
- Docker (install it yourself, or pair this role with a `docker` role — [community.docker](https://docs.ansible.com/projects/ansible/latest/collections/community/docker/index.html) collection required for compose)

## Quick start

```yaml
# requirements.yaml
collections:
  - name: community.docker
    version: ">=3.10.0"

roles:
  - name: ryclarke.authelia
```

```bash
ansible-galaxy install -r requirements.yaml
```

Minimal playbook:

```yaml
- hosts: auth
  become: true
  roles:
    - ryclarke.authelia
```

Core variables:

```yaml
authelia_domain: "auth.example.com" # your Authelia public domain
authelia_smtp_address: "submission://smtp.example.com:587"
authelia_smtp_username: "auth@example.com"

# secrets — set these in an ansible-vault file, _NEVER_ in plaintext
authelia_jwt_secret: "..."
authelia_session_secret: "..."
authelia_storage_encryption_key: "..."
authelia_smtp_password: "..."
authelia_ldap_password: "..."
authelia_ldap_jwt_secret: "..." # managed lldap only
authelia_ldap_key_seed: "..."   # managed lldap only
```
> For bootstrapping a new implementation, see the official guide for [generating secrets](https://www.authelia.com/reference/guides/generating-secure-values/).

Deploy with `ansible-playbook --ask-vault-pass`, then open `https://auth.example.com` and create your first user in lldap.

## Configuration Philosophy

This role separates its variables into two categories, matching how they behave over the lifetime of a deployment:

- **Usage Configuration** — what Authelia protects and how users authenticate against it (ACLs, OIDC clients, authz endpoints, network definitions, user attributes). These evolve as your applications change: expect to append ACL rules and OIDC clients routinely.

- **Integration Configuration** — how the stack connects to backing services (SMTP, LDAP, storage, Redis). These define your infrastructure topology and should stay stable unless you deliberately change providers or architectures.

The behavioral difference matters: usage blocks are generally **extended** (appended to) as your deployment grows, while integration blocks, if overridden, **replace their defaults entirely** — there is no merging. See each section below for the specifics; one exception, authorization endpoints, also replaces wholesale despite living in the usage side and carries a warning in its section.

## Usage Configuration
### Access Control Rules (ACLs)
Define which users/groups can access which domains. See the official Authelia [ACL configuration](https://www.authelia.com/configuration/security/access-control/):
```yaml
authelia_acl_default_policy: deny
authelia_acl_rules:
  - policy: one_factor
    domain:
      - "app1.example.com"
      - "app2.example.com"
    subject:
      - "group:users"

  - policy: two_factor
    domain:
      - "*.admin.example.com"
    subject:
      - "group:admins"
  ...
```
> ℹ️ Use `authelia_network_definitions` to create named CIDR groups (e.g., lan, offsite) and reference them in rules via `subject: ["network:lan"]` for IP-based allowlists. See [Rule Operators](https://www.authelia.com/reference/guides/rule-operators/) for syntax.

### OpenID Connect (OIDC) Clients
Configure OAuth2/OIDC clients for your backend applications. See the official Authelia [OIDC client configuration](https://www.authelia.com/configuration/identity-providers/openid-connect/clients/):
```yaml
authelia_oidc_clients:
  - client_name: "My App"
    client_id: "app-client-id"
    client_secret: "$pbkdf2-sha512$..." # Hashed secret
    authorization_policy: "two_factor"
    redirect_uris:
      - "https://myapp.example.com/sso/redirect"
    scopes:
      - "openid"
      - "profile"
      - "email"
  ...
```
> ℹ️ The client secret here should be a **digest**, not the full plaintext secret! See [Generating Secrets](https://www.authelia.com/reference/guides/generating-secure-values/).

### Authorization endpoints
By default the role configures nothing and Authelia applies its built-in endpoints.

Provide `authelia_authz_endpoints` only when you need to customize an endpoint's authentication strategies. See the official Authelia [authz endpoints configuration](https://www.authelia.com/configuration/miscellaneous/server-endpoints-authz/) and [proxy authentication guide](https://www.authelia.com/reference/guides/proxy-authorization/):

```yaml
authelia_authz_endpoints:
  forward-auth:
    implementation: ForwardAuth
    authn_strategies:
      - name: HeaderAuthorization
        schemes: [Basic]
        scheme_basic_cache_lifespan: 0
      - name: CookieSession
  ...
```
> ⚠️ **WARNING:** If any endpoints are set, the provided list becomes the complete enabled set — Authelia's defaults are **removed entirely**, not merged. Required default endpoints must be re-declared in full alongside custom ones.

### Network Definitions
Reusable named networks for use in ACL rules. See the official Authelia [network definitions configuration](https://www.authelia.com/configuration/definitions/network/):
```yaml
authelia_network_definitions:
  lan:
    - "192.168.1.0/24"
```
> Usage: Reference these in ACL rules: `subject: ["network:lan"]`. This keeps rules clean and avoids hardcoding IPs.

### User Attributes
Custom attributes mapped from LDAP or local users, available for use in ACL rules and OIDC claims. See the official Authelia [user attributes configuration](https://www.authelia.com/configuration/definitions/user-attributes/):
```yaml
authelia_user_attributes:
  department:
    display_name: "Department"
    required: false

  manager:
    display_name: "Manager"
    required: false
```
> Usage: Once defined, you can reference these in ACL rules (e.g., `subject:["attribute:department=Engineering"]`) or expose them in OIDC claims.

### Advanced: Custom configuration template

For radically different usage configuration not expressible through the structured
variables, point the role at your own template:

```yaml
authelia_configuration_template: /path/to/my-configuration.yaml.j2
```
Defaults to the role-bundled configuration.yaml.j2. A custom path must be absolute (or differently named) — the role's bundled template wins relative-path resolution. All authelia_* variables remain in scope, so you can use them in your own template.

## Integration Configuration

The role is opinionated by default but doesn't lock you in. Each backing service has two knobs: whether the role *deploys* it, and where Authelia *connects* to it.

Unmanaged services simply aren't deployed — no orphan containers, directories, or secrets.

### Caddy Reverse Proxy
Enable the bundled Caddy with custom DNS plugins:
```yaml
authelia_caddy_managed: true
authelia_caddy_plugins:
  - github.com/caddy-dns/cloudflare
authelia_caddy_env:
  CF_API_TOKEN: "..."
```

The role's Caddyfile is intentionally minimal — a hardened global block and a single
directive:

```caddy
import /etc/caddy/sites/*.caddy
```

Everything else is yours. Any .caddy file you place in `{{ authelia_root }}/caddy/sites/` is [imported](https://caddyserver.com/docs/caddyfile/directives/import) into the running config (glob expansion is alphabetical, so use numeric prefixes to control ordering — snippets first, sites after):
```
caddy/sites/
├── 00-common.caddy
├── 10-example-com.caddy
└── 20-other-domain.caddy
```

A minimal site that fronts an internal service with Authelia [forward-auth](https://www.authelia.com/reference/guides/proxy-authorization/):
```caddy
# 10-example-com.caddy
app.example.com {
	forward_auth 127.0.0.1:9091 {
		uri /api/authz/forward-auth
		copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
	}

	reverse_proxy 192.168.1.50:3000
}
```

### SMTP Configuration
Authelia requires email to send password resets, notifications, and verification codes. You can configure this in three ways depending on your needs.

#### 1. Simple Setup (recommended) 🗸
For most users, setting just the server address and username is sufficient. The role automatically fills in the sender address and other details based on your domain:
```yaml
authelia_smtp_address: "submission://smtp.gmail.com:587"
authelia_smtp_username: "noreply@example.com"
authelia_smtp_password: "..."  # SECRET value
```

#### 2. Advanced Configuration 🔧
If you need custom TLS settings, a specific sender name, or other non-standard options, provide the full `authelia_smtp` block:
```yaml
authelia_smtp_password: "..."  # SECRET value
authelia_smtp:
  address: "submission://relay.internal.corp:587"
  username: "auth-relay"
  sender: "Security Team <security@internal.corp>"
  identifier: "auth.internal.corp"
  # Custom TLS options (example)
  require_tls: true
  disable_starttls: false
```
> Note: The entire `authelia_smtp` block is replaced if set. Do not attempt to merge partial settings. See the official Authelia documentation for [SMTP configuration](https://www.authelia.com/configuration/notifications/smtp/).

#### 3. Disable Notifications (testing only) ⚠️
You can disable email entirely, but this will prevent users from resetting passwords or recovering accounts. Only use this for testing:
```yaml
authelia_smtp_enabled: false
```

### LDAP Authentication
Authelia delegates user lookup and group membership to an LDAP directory. The role defaults to deploying lldap (Lightweight LDAP) for simplicity, but supports any standard LDAP server (Active Directory, FreeIPA, OpenLDAP).

#### 1. Managed LLDAP (default)
The role deploys a dedicated lldap container and automatically derives the connection details from your domain. You only need to provide the admin password:
```yaml
authelia_ldap_managed: true
authelia_ldap_password: "..."  # SECRET value
```
> The role sets base_dn to `DC=<your-domain-parts>` and user to `UID=admin,OU=people,DC=<your-domain-parts>` for you automatically.

#### 2. External LDAP / Active Directory
Point Authelia at an existing directory service. You must disable the managed container and provide the full connection block:
```yaml
authelia_ldap_managed: false
authelia_ldap_password: "..."  # SECRET value
authelia_ldap:
  implementation: ldap
  address: "ldaps://directory.internal:636"
  base_dn: "DC=example,DC=com"
  user: "CN=Admin,OU=Service Accounts,DC=example,DC=com"
  # Add custom TLS certificates, filters, or timeout settings here
```
> See the official Authelia documentation for [LDAP configuration](https://www.authelia.com/configuration/first-factor/ldap/) and [integrations](https://www.authelia.com/reference/integrations/ldap-integrations/).

### Persistent Storage
Authelia's persistent state (users, sessions, TOTP registrations, OIDC consents). Two independent choices: whether Postgres is used at all, and whether this role deploys it.

#### 1. Local Storage (default)
SQLite on the deployment volume — sufficient and lean for single-instance deployments:
```yaml
authelia_storage_backend: local
```

#### 2. Managed Postgres
Just flip the backend flag — the role deploys a hardened container and wires Authelia to it. No block override needed:
```yaml
authelia_storage_backend: postgres
authelia_storage_postgres_managed: true
authelia_storage_postgres_password: "..."  # SECRET value
```

#### 3. External Postgres
Point Authelia at an existing instance — managed flag off, full block provided:
```yaml
authelia_storage_backend: postgres
authelia_storage_postgres_managed: false
authelia_storage_postgres_password: "..."  # SECRET value
authelia_storage_postgres:
  address: "tcp://db.internal:5432"
  database: authelia
  username: authelia
  # TLS and other connection settings as needed for your server
```
> See the official Authelia documentation for [Postgres configuration](https://www.authelia.com/configuration/storage/postgres/).

### Redis Sessions
Redis matters only for multi-replica Authelia or cross-restart session sharing. It's off by default — single-instance deployments don't need it.

#### 1. Disabled (default)
```yaml
authelia_redis_enabled: false
```

#### 2. Managed Redis
```yaml
authelia_redis_enabled: true
authelia_redis_managed: true
authelia_redis_password: "..."  # SECRET value, optional
```

#### 3. External Redis
```yaml
authelia_redis_enabled: true
authelia_redis_managed: false
authelia_redis_password: "..."  # SECRET value
authelia_redis:
  host: redis.internal
  port: 6379
  # TLS / connection settings as needed
```
> See the official Authelia documentation for [Redis configuration](https://www.authelia.com/configuration/session/redis/).

### Extending the Compose project

Define custom services under `authelia_compose_extra_services` for the Compose project to be deployed alongside Authelia:
```yaml
authelia_compose_extra_services:
  whoami-exporter:
    image: traefik/whoami:latest
    networks: ["{{ authelia_network_name }}"]
  ...
```

Environment variables for the whole project go in `authelia_compose_extra_envs`, rendered into the compose `.env` alongside the managed values:
```yaml
authelia_compose_extra_envs:
  KEY: value
  ...
```

### Images

All container images are customizable, defaulting to upstream tags:

| Variable                        | Default                                        |
|---------------------------------|------------------------------------------------|
| `authelia_images_authelia`      | `docker.io/authelia/authelia:latest`           |
| `authelia_images_lldap`         | `docker.io/lldap/lldap:latest-alpine-rootless` |
| `authelia_images_postgres`      | `postgres:18-alpine`                           |
| `authelia_images_redis`         | `redis:8-alpine`                               |
| `authelia_images_caddy_builder` | `caddy:2-builder`                              |
| `authelia_images_caddy_runtime` | `caddy:2-alpine`                               |

Production deployments should pin these to digests (`image@sha256:...`) — `latest` defaults are convenient for first runs but make the deployed version dependent on pull timing, which undermines reproducibility and supply-chain auditing.

## Configuration highlights

| Variable | Default | Purpose |
|---|---|---|
| `authelia_root` | `/opt/authelia` | Deployment root (derived from `authelia_project_name`) |
| `authelia_log_level` | `info` | Authelia log level |
| `authelia_theme` | `""` | `light`, `dark`, `grey`, `auto` |
| `authelia_acl_default_policy` | `deny` | Default ACL policy (`deny` + explicit allows is best practice) |
| `authelia_acl_rules` | `[]` | Access-control rules, injected into `access_control` |
| `authelia_oidc_clients` | `[]` | OpenID Connect clients, injected into `identity_providers` |
| `authelia_network_definitions` | `{}` | Named CIDR lists reused in ACL rules |
| `authelia_user_attributes` | `{}` | Custom attribute definitions surfaced in OIDC claims and ACL rules ([docs](https://www.authelia.com/configuration/definitions/user-attributes/)) |
| `authelia_authz_endpoints` | `{}` | Authz endpoint definitions for reverse-proxy integration |
| `authelia_hardening` | see defaults | Per-service container hardening (uids, caps, read-only) |
| `authelia_compose_extra_services` | `{}` | Extra service definitions merged into the compose services |
| `authelia_compose_extra_envs` | `{}` | Extra env keys merged into the compose `.env` |

> Secrets (`authelia_jwt_secret`, `authelia_ldap_password`, …) are rendered as files under `secrets/` and exposed to containers via compose secret mounts.

**Note on container hardening:** Authelia's internal healthcheck writes to its filesystem. When read_only: true (enabled by default), the role automatically sets disable_healthcheck: true in the config. These are coupled — flip one and the other follows.

## Contributing

Bug reports and PRs welcome. The role stays deliberately opinionated: I don't have the bandwidth to maintain a catch-all solution for every use case. This role aims to be a solid fits-most baseline instead.

### Render tests

The render harness uses the `minimal` fixture by default. It renders into the workspace-relative `./tmp` directory and runs the Ansible assertions. CI separately validates the generated Compose file and runs Authelia's built-in configuration validator in Docker. Install the role's collection first:

```bash
ansible-galaxy collection install -r requirements.yaml
```

Run the default fixture, select another fixture by basename, or exercise the isolated Ansible check-mode path:

```bash
# run ansible-lint
make lint

# run the playbook against fixture config with --check
make check
make check-{fixture}

# run the playbook against fixture config
make test
make test-{fixture}

# validate locally rendered output
# requires Docker running locally and the output of `make test`
make validate
make validate-{fixture}
```

The local render tests require Ansible only. `make validate` additionally requires Docker or Podman with a Compose provider. All fixtures render to `./tmp`, which is cleared before each run and left behind afterward for inspection. Tests run without privilege escalation and use output owned by the invoking user. CI runs `make test` and `make validate` for every file in `tests/fixtures/`. These checks validate generated configuration only; they do not start the full Authelia stack or test SMTP delivery, LDAP authentication, or database connectivity.
