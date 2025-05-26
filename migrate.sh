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
[ -d "$NEW_DATA" ] && [ -z "$(ls -A "$NEW_DATA")" ] || { echo "❌ New data dir must exist and be empty"; exit 1; }

# Set permissions and initialize
echo "🔧 Setting permissions and initializing new cluster..."
chown -R "$CURRENT_UID:$CURRENT_GID" "$NEW_DATA"
run_as_user "$NEW_BIN/initdb -D $NEW_DATA"

# Clean stale pid file
echo "🧹 Cleaning stale pid file..."
rm -f "$OLD_DATA/postmaster.pid"

# Run pre-upgrade check
echo "🔎 Running pre-upgrade check..."
cd /tmp
if ! run_as_user "$NEW_BIN/pg_upgrade \
    --old-datadir=$OLD_DATA \
    --new-datadir=$NEW_DATA \
    --old-bindir=$OLD_BIN \
    --new-bindir=$NEW_BIN \
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
    --copy"; then
    echo "❌ Upgrade failed"
    exit 1
fi

echo "🎉 Migration complete: $OLD_VERSION -> $NEW_VERSION"