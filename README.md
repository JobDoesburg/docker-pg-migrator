# 🐘 PostgreSQL Data Migrator (Safe `pg_upgrade` via Docker)

This project provides a **safe, containerized way to migrate PostgreSQL data from one version to another** using `pg_upgrade`. It uses Docker and `docker-compose` to encapsulate the process and ensures that the original data remains untouched.

---

## 🚀 What It Does

- 📦 Mounts two PostgreSQL data volumes:
  - 🔒 `old_pgdata` (read/write): contains data from the old PostgreSQL version  
    ➤ Although mounted as `read/write`, this is **safe** — `pg_upgrade` only starts the old server temporarily and reads from the data directory.  
    ➤ It **does not alter** or overwrite any of the original database files.
  - 🆕 `new_pgdata` (read/write): will store the upgraded data
- 🔧 Runs a UID-aware, version-safe PostgreSQL upgrade using `pg_upgrade --copy`
- 🧼 Leaves the original data intact
- 🔄 Supports migrations like 13 ➜ 16
- 🧠 Automatically patches locale issues
- 🧪 CI tested via GitHub Actions

---

## 📦 Build & Run

### 🛠️ Using Docker Compose

```yaml
# docker-compose.yml
version: '3.9'

services:
  pg-migrator:
    build:
      context: .
      args:
        OLD_PG_VERSION: "13"
        NEW_PG_VERSION: "16"
    volumes:
      - old_pgdata:/var/lib/postgresql/old:rw
      - new_pgdata:/var/lib/postgresql/new:rw
    environment:
      UID: 70
      GID: 70
      PGUSER_NAME: testuser
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

---

### 🐳 Using plain Docker

```bash
docker build \
  --build-arg OLD_PG_VERSION=13 \
  --build-arg NEW_PG_VERSION=16 \
  -t pg-migrator:13-to-16 .

docker run --rm \
  -v $PWD/pgdata-old:/var/lib/postgresql/old:rw \
  -v $PWD/pgdata-new:/var/lib/postgresql/new:rw \
  -e OLD_PG_VERSION=13 \
  -e NEW_PG_VERSION=16 \
  -e UID=70 \
  -e GID=70 \
  -e PGUSER_NAME=testuser \
  pg-migrator:13-to-16
```