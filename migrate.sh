#!/bin/bash
set -euo pipefail

OLD_VERSION=${OLD_PG_VERSION:-13}
NEW_VERSION=${NEW_PG_VERSION:-16}
POSTGRES_USER=${POSTGRES_USER:-""}  # Optional - will auto-detect if not provided
OLD_DATA="/var/lib/postgresql/old"
NEW_DATA="/var/lib/postgresql/new"
OLD_BIN="/usr/lib/postgresql/$OLD_VERSION/bin"
NEW_BIN="/usr/lib/postgresql/$NEW_VERSION/bin"

CURRENT_UID=${UID:-$(id -u)}
CURRENT_GID=${GID:-$(id -g)}

# Ensure system user exists for the UID (this is the postgres process user)
if ! getent passwd "$CURRENT_UID" >/dev/null; then
    echo "🛠 Creating system user entry for UID $CURRENT_UID..."
    echo "postgres::${CURRENT_UID}:${CURRENT_GID}:PostgreSQL:/var/lib/postgresql:/bin/bash" >> /etc/passwd
fi

run_as_user() {
    setpriv --reuid="$CURRENT_UID" --regid="$CURRENT_GID" --init-groups bash -c "$*"
}

# Basic validation
[ -d "$OLD_DATA" ] || { echo "❌ Old data not found: $OLD_DATA"; exit 1; }

# Clean up new data directory if it exists and isn't empty
if [ -d "$NEW_DATA" ] && [ -n "$(ls -A "$NEW_DATA")" ]; then
    echo "🧹 New data directory not empty, cleaning it..."
    rm -rf "$NEW_DATA"/*
fi

# Ensure new data directory exists
mkdir -p "$NEW_DATA"

# Set permissions and initialize
echo "🔧 Setting permissions and initializing new cluster..."
chown -R "$CURRENT_UID:$CURRENT_GID" "$NEW_DATA"
run_as_user "$NEW_BIN/initdb -D $NEW_DATA"

# Clean stale pid file and ensure clean shutdown
echo "🧹 Ensuring old cluster is properly shut down..."
rm -f "$OLD_DATA/postmaster.pid"

# Try to start and cleanly shut down the old cluster to ensure it's in a clean state
echo "🔄 Performing clean shutdown of old cluster..."
if run_as_user "$OLD_BIN/pg_ctl -D $OLD_DATA -o '-p 50431 -k /tmp' -w start" 2>/dev/null; then
    echo "✅ Old cluster started, performing clean shutdown..."
    run_as_user "$OLD_BIN/pg_ctl -D $OLD_DATA -m smart stop"
else
    echo "ℹ️ Old cluster was already stopped"
fi

# Ensure no stale processes or files remain
rm -f "$OLD_DATA/postmaster.pid" "$NEW_DATA/postmaster.pid" 2>/dev/null || true

# Detect the actual install user from the old cluster
echo "🔍 Detecting the original install user from old cluster..."
run_as_user "$OLD_BIN/pg_ctl -D $OLD_DATA -o '-p 50431 -k /tmp' -w start"

# Get the install user (usually has OID 10 or is the bootstrap superuser)
INSTALL_USER=$(run_as_user "$OLD_BIN/psql -h /tmp -p 50431 -d postgres -t -c \"SELECT rolname FROM pg_roles WHERE oid = 10;\"" | xargs)

# If no user with OID 10, get the first superuser (likely the install user)
if [ -z "$INSTALL_USER" ]; then
    INSTALL_USER=$(run_as_user "$OLD_BIN/psql -h /tmp -p 50431 -d postgres -t -c \"SELECT rolname FROM pg_roles WHERE rolsuper = true ORDER BY oid LIMIT 1;\"" | xargs)
fi

run_as_user "$OLD_BIN/pg_ctl -D $OLD_DATA -m fast stop"

echo "👤 Found install user: $INSTALL_USER"

# Create the install user in new cluster
echo "👤 Ensuring install user '$INSTALL_USER' exists in new cluster..."
run_as_user "$NEW_BIN/pg_ctl -D $NEW_DATA -o '-p 50432 -k /tmp' -w start"
run_as_user "$NEW_BIN/psql -h /tmp -p 50432 -d postgres -c \"CREATE USER \\\"$INSTALL_USER\\\" WITH SUPERUSER;\" 2>/dev/null || true"

# Also create the application user if different
if [ -n "$POSTGRES_USER" ] && [ "$POSTGRES_USER" != "$INSTALL_USER" ]; then
    echo "👤 Also creating application user '$POSTGRES_USER'..."
    run_as_user "$NEW_BIN/psql -h /tmp -p 50432 -d postgres -c \"CREATE USER \\\"$POSTGRES_USER\\\" WITH SUPERUSER;\" 2>/dev/null || true"
fi

run_as_user "$NEW_BIN/pg_ctl -D $NEW_DATA -m fast stop"

# Run pre-upgrade check
echo "🔎 Running pre-upgrade check..."
cd /tmp
if ! run_as_user "$NEW_BIN/pg_upgrade \
    --old-datadir=$OLD_DATA \
    --new-datadir=$NEW_DATA \
    --old-bindir=$OLD_BIN \
    --new-bindir=$NEW_BIN \
    --username=\"$INSTALL_USER\" \
    --check"; then
    echo "❌ Pre-upgrade check failed"
    exit 1
fi

echo "✅ Check passed"

# Run upgrade
echo "🚀 Starting migration..."
if ! run_as_user "$NEW_BIN/pg_upgrade \
    --old-datadir=$OLD_DATA \
    --new-datadir=$NEW_DATA \
    --old-bindir=$OLD_BIN \
    --new-bindir=$NEW_BIN \
    --username=\"$INSTALL_USER\" \
    --copy"; then
    echo "❌ Upgrade failed"
    exit 1
fi

echo "🎉 Migration complete: $OLD_VERSION -> $NEW_VERSION"
echo "📌 ALL users, databases, and data have been migrated!"