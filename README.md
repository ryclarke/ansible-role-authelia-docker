# ansible-role-authelia-docker

An opinionated Ansible role that deploys a complete, hardened [Authelia](https://www.authelia.com) SSO stack via Docker Compose: **Authelia + lldap + Postgres + Redis**, with an optional **Caddy** reverse proxy that builds a custom image with the DNS plugins of your choice.

Designed for single-instance homelab or small-business deployments. Boring, proven, minimal moving parts — every container runs as a pinned unprivileged user with `cap_drop: ALL`, `no-new-privileges`, and a read-only rootfs where possible.

## Requirements

- Ansible 2.15+
- Debian-based target with Python 3
- Docker (install it yourself, or pair this role with a `docker` role — [community.docker](https://galaxy.ansible.com/ui/repo/community/docker/) collection required for compose)

## Quick start

```yaml
# requirements.yml
roles:
  - src: https://github.com/ryclarke/ansible-role-authelia-docker
    name: authelia
```

```bash
ansible-galaxy install -r requirements.yml
```

Minimal playbook:

```yaml
- hosts: auth
  become: true
  roles:
    - authelia
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
authelia_ldap_password: "..."
authelia_smtp_password: "..."
```

Deploy with `ansible-playbook --ask-vault-pass`, then open `https://auth.example.com` and create your first user in lldap.

## Bring your own backends

The role is opinionated by default but doesn't lock you in. Each backing service has two knobs: whether the role *deploys* it, and where Authelia *connects* to it.

```yaml
# Use an existing Postgres instead of the bundled one
authelia_storage_backend: postgres
authelia_storage_postgres_managed: false
authelia_storage_postgres_connection:
  address: "tcp://db.internal:5432"
  database: authelia
  username: authelia
authelia_storage_postgres_password: "..."   # must match the external DB

# External LDAP? Point at it and stop deploying lldap
authelia_ldap_managed: false
authelia_ldap_connection:
  implementation: ldap
  address: "ldap://directory.internal:389"
  ...

# Redis is off by default — it only matters for multi-replica Authelia.
# Turn it on with:
authelia_redis_enabled: true
authelia_redis_managed: true
authelia_redis_password: "..."

# Already happy with your own reverse proxy? Caddy is disabled by default.
# Enable the bundled one (with custom DNS plugins) via:
authelia_caddy_managed: true
authelia_caddy_plugins:
  - github.com/caddy-dns/cloudflare
authelia_caddy_env:
  CF_API_TOKEN: "..." # rendered to .env, not into the compose file
```

Unmanaged services simply aren't deployed — no orphan containers, directories, or secrets.

### LDAP / lldap

For lldap, only `authelia_domain` is required — `base_dn` and `bind_user` derive automatically from your domain:

| Explicit vars | Result |
|---|---|
| None | `DC=<domain>` / `UID=admin,OU=people,DC=<domain>` |
| `base_dn` only | yours / `UID=admin,OU=people,<your_base_dn>` |
| `base_dn` + `user` | yours / yours |

For non-lldap implementations (Active Directory, freeIPA, etc.), both are required explicitly.

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
| `authelia_authz_endpoints` | forward-auth | Authz endpoint definitions for reverse-proxy integration |
| `authelia_hardening` | see defaults | Per-service container hardening (uids, caps, read-only) |
| `authelia_env_extra` | `{}` | Extra env keys merged into the compose `.env` |

Secrets (`authelia_jwt_secret`, `authelia_ldap_password`, …) are rendered as files under `secrets/` and exposed to containers via compose secret mounts.

**Note on container hardening:** Authelia's internal healthcheck writes to its filesystem. When read_only: true (enabled by default), the role automatically sets disable_healthcheck: true in the config. These are coupled — flip one and the other follows.

## Contributing

Bug reports and PRs welcome. The role stays deliberately opinionated: I don't have the bandwidth to maintain a catch-all solution for every use case. This role aims to be a solid fits-most baseline instead. Please include validation (`ansible-lint`) with changes; a render-check CI job guards the compose/config templates.
