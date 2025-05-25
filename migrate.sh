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
USER_NAME=pguser

# Add passwd entry if UID not defined
if ! getent passwd "$CURRENT_UID" >/dev/null; then
    echo "🛠 No passwd entry for UID $CURRENT_UID. Creating $USER_NAME..."
    echo "$USER_NAME::${CURRENT_UID}:${CURRENT_GID}:PostgreSQL:/var/lib/postgresql:/bin/bash" >> /etc/passwd
fi

echo "✅ Running migration as UID=$CURRENT_UID (user $USER_NAME)"

as_migrator_user() {
    setpriv --reuid="$CURRENT_UID" --regid="$CURRENT_GID" --init-groups bash -c "$*"
}

echo "🔍 Checking directories..."
[ -d "$OLD_DATA" ] || { echo "❌ Old data directory not found: $OLD_DATA"; exit 1; }
[ -d "$NEW_DATA" ] || { echo "❌ New data directory not found: $NEW_DATA"; exit 1; }

echo "🔎 Checking that new data directory is empty..."
[ -z "$(ls -A "$NEW_DATA")" ] || { echo "❌ New data directory ($NEW_DATA) is not empty. Aborting."; exit 1; }

echo "🔧 Fixing permissions on new data directory..."
chown -R "$CURRENT_UID:$CURRENT_GID" "$NEW_DATA"

TMP_WORKDIR="/tmp/pg_upgrade_work"
mkdir -p "$TMP_WORKDIR"
chown "$CURRENT_UID:$CURRENT_GID" "$TMP_WORKDIR"

echo "📁 Initializing new data cluster..."
as_migrator_user "$NEW_BIN/initdb -D $NEW_DATA"
echo "✅ Initialization complete"

# Remove stale postmaster.pid
if [ -f "$OLD_DATA/postmaster.pid" ]; then
    echo "🧹 Removing stale postmaster.pid from $OLD_DATA"
    rm -f "$OLD_DATA/postmaster.pid"
fi

echo "🔎 Running pre-upgrade check..."
if ! as_migrator_user "cd $TMP_WORKDIR && $NEW_BIN/pg_upgrade \
    --old-datadir=$OLD_DATA \
    --new-datadir=$NEW_DATA \
    --old-bindir=$OLD_BIN \
    --new-bindir=$NEW_BIN \
    --check"; then
    echo "❌ Pre-upgrade check failed"
    find "$NEW_DATA/pg_upgrade_output.d" -name pg_upgrade_server.log -exec cat {} + || true
    chmod -R a+r "$NEW_DATA/pg_upgrade_output.d" || true
    exit 1
fi

echo "✅ Check passed"

echo "🚀 Starting upgrade..."
if ! as_migrator_user "cd $TMP_WORKDIR && $NEW_BIN/pg_upgrade \
    --old-datadir=$OLD_DATA \
    --new-datadir=$NEW_DATA \
    --old-bindir=$OLD_BIN \
    --new-bindir=$NEW_BIN \
    --jobs=2 \
    --verbose \
    --copy \
    --write-planner-stats"; then
    echo "❌ Upgrade failed"
    find "$NEW_DATA/pg_upgrade_output.d" -name pg_upgrade_server.log -exec cat {} + || true
    chmod -R a+r "$NEW_DATA/pg_upgrade_output.d" || true
    exit 1
fi

chmod -R a+r "$NEW_DATA/pg_upgrade_output.d" || true

echo ""
echo "🎉 Migration complete!"
echo "📌 New PostgreSQL $NEW_VERSION data is ready at $NEW_DATA"
echo "🛑 Old data at $OLD_DATA remains untouched (read-only mount)"