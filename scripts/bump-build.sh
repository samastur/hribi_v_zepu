#!/bin/sh
# Increments the shared build number (CURRENT_PROJECT_VERSION) in project.yml
# and regenerates the Xcode project. Run before each TestFlight upload.
set -e
cd "$(dirname "$0")/.."

current=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *//p' project.yml | head -1)
if [ -z "$current" ]; then
  echo "error: CURRENT_PROJECT_VERSION not found in project.yml" >&2
  exit 1
fi
next=$((current + 1))
sed -i '' "s/^\( *CURRENT_PROJECT_VERSION: *\).*/\1$next/" project.yml
xcodegen generate

version=$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' project.yml | head -1)
echo "Build number bumped: $current -> $next (version $version)"
echo "Next: commit, then in Xcode: Product > Archive > Distribute App > TestFlight"
