#!/bin/bash
set -euo pipefail

OLD_VERSION=${OLD_PG_VERSION:-13}
NEW_VERSION=${NEW_PG_VERSION:-16}
OLD_DATA="/var/lib/postgresql/old"
NEW_DATA="/var/lib/postgresql/new"
OLD_BIN="/usr/lib/postgresql/$OLD_VERSION/bin"
NEW_BIN="/usr/lib/postgresql/$NEW_VERSION/bin"

CURRENT_UID=${UID:-$(id -u)}
CURRENT_GID=${GID:-$(id -g)}

# Ensure user exists for the UID
if ! getent passwd "$CURRENT_UID" >/dev/null; then
    echo "🛠 Creating user entry for UID $CURRENT_UID..."
    echo "pguser::${CURRENT_UID}:${CURRENT_GID}:PostgreSQL:/var/lib/postgresql:/bin/bash" >> /etc/passwd
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

# Clean stale pid file
echo "🧹 Cleaning stale pid file..."
rm -f "$OLD_DATA/postmaster.pid"

# Detect existing superuser from old cluster
echo "🔍 Detecting existing superuser..."
run_as_user "$OLD_BIN/pg_ctl -D $OLD_DATA -o '-p 50431' -w start"
EXISTING_USER=$(run_as_user "$OLD_BIN/psql -p 50431 -d postgres -t -c \"SELECT rolname FROM pg_roles WHERE rolsuper = true LIMIT 1;\"" | xargs)
run_as_user "$OLD_BIN/pg_ctl -D $OLD_DATA -m fast stop"

echo "👤 Found existing superuser: $EXISTING_USER"

# Create the same user in new cluster if it doesn't exist
echo "👤 Ensuring user '$EXISTING_USER' exists in new cluster..."
run_as_user "$NEW_BIN/pg_ctl -D $NEW_DATA -o '-p 50432' -w start"
run_as_user "$NEW_BIN/psql -p 50432 -d postgres -c \"CREATE USER \\\"$EXISTING_USER\\\" WITH SUPERUSER;\" 2>/dev/null || true"
run_as_user "$NEW_BIN/pg_ctl -D $NEW_DATA -m fast stop"

# Run pre-upgrade check
echo "🔎 Running pre-upgrade check..."
cd /tmp
if ! run_as_user "$NEW_BIN/pg_upgrade \
    --old-datadir=$OLD_DATA \
    --new-datadir=$NEW_DATA \
    --old-bindir=$OLD_BIN \
    --new-bindir=$NEW_BIN \
    --username=\"$EXISTING_USER\" \
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
    --username=\"$EXISTING_USER\" \
    --copy"; then
    echo "❌ Upgrade failed"
    exit 1
fi

echo "🎉 Migration complete: $OLD_VERSION -> $NEW_VERSION"