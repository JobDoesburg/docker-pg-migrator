# 🐘 PostgreSQL Data Migrator (Safe pg_upgrade via Docker)

This project provides a **safe, containerized way to migrate PostgreSQL data from one version to another** using `pg_upgrade`. It uses Docker and `docker-compose` to encapsulate the process and ensures that the original data remains untouched.

---

## 🚀 What It Does

- Mounts two PostgreSQL data volumes:
  - 🔒 `old_pgdata` (read-only): contains data from the old PostgreSQL version
  - 🆕 `new_pgdata` (read-write): will store the upgraded data
- Runs a version-safe, in-place PostgreSQL upgrade using `pg_upgrade`
- Leaves the original data intact
- Supports multiple PostgreSQL version upgrades (e.g., 13 ➜ 16)


## 📦 Build & Run

### Using Docker Compose
```yaml
# docker-compose.yml
version: '3.9'

services:
  pg-migrator:
    build:
      context: .
      args:
        OLD_PG_VERSION: "12"
        NEW_PG_VERSION: "15"
    volumes:
      - old_pgdata:/var/lib/postgresql/old:ro
      - new_pgdata:/var/lib/postgresql/new:rw
    restart: "no"

volumes:
  old_pgdata:
  new_pgdata:
```

Then run:

```bash
docker-compose build
docker-compose up
```

### Or use plain Docker:

```bash
docker build \
  --build-arg OLD_PG_VERSION=13 \
  --build-arg NEW_PG_VERSION=16 \
  -t pg-migrator:13-to-16 .
docker run --rm \
 -v old_pgdata:/var/lib/postgresql/old:ro \
 -v new_pgdata:/var/lib/postgresql/new:rw \
 pg-migrator
```