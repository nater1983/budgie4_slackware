#!/bin/bash
# ------------------------------------------
# Budgie + Dependencies Source Tarball Generator
# (Slackware-friendly, supports partial categories)
# ------------------------------------------

set -e

ROOT_DIR="$(pwd)"
GITHUB_BASE_URL="https://github.com/BuddiesOfBudgie"
DEST_DIR="$CWD/src"

mkdir -p "$DEST_DIR"

# -------------------------------
# Colors
# -------------------------------
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BLUE='\033[1;34m'
BOLD='\033[1m'
NC='\033[0m'

# -------------------------------
# 1. Pantheon Core Components
# -------------------------------
declare -A CORE_REPOS=(
  ["magpiewm"]="magpie"
  ["budgie-session"]="budgie-session"
  ["budgie-desktop-view"]="budgie-desktop-view"
  ["budgie-control-center"]="budgie-control-center"
  ["budgie-backgrounds"]="budgie-backgrounds"
  ["budgie-desktop"]="budgie-desktop"
  ["budgie-screensaver"]="budgie-screensaver"
)

# -------------------------------
# Process a single repository
# -------------------------------
process_repo() {
  local PRGNAM=$1
  local REPO_NAME=$2

  echo -e "${BLUE}→ Processing ${BOLD}$REPO_NAME${NC}..."

  local GITDIR
  GITDIR=$(mktemp -dt "$PRGNAM.git.XXXXXX")

  trap 'rm -rf "$GITDIR"' EXIT INT TERM

  git clone --depth 1 "$GITHUB_BASE_URL/$REPO_NAME.git" "$GITDIR" >/dev/null 2>&1 || {
    echo -e "${RED}❌ Failed to clone $REPO_NAME${NC}"
    return 1
  }

  cd "$GITDIR"
  git fetch --tags >/dev/null 2>&1 || echo -e "${YELLOW}⚠️  No tags found for $REPO_NAME${NC}"

  # Determine latest tag (if any)
  local LATEST_TAG
  # Get only “clean” numeric tags (e.g., 8.0.1) ignoring -debian, -ubuntu, etc.
  LATEST_TAG=$(git tag --sort=-v:refname | grep -E '^v?[0-9]+(\.[0-9]+)*$' | head -n1)

  local VERSION
  if [ -n "$LATEST_TAG" ]; then
    echo -e "${YELLOW}→ Checking out tag:${NC} $LATEST_TAG"
    # Use refs/tags/ explicitly to avoid ambiguity with branches
    git checkout -q "refs/tags/$LATEST_TAG"
    VERSION=${LATEST_TAG#v}
  else
    echo -e "${YELLOW}⚠️  No tags found, using latest commit${NC}"
    VERSION=$(git log -1 --date=format:%Y%m%d --pretty=format:%cd.%h)
  fi

  # Remove distro-specific suffixes from version string
  VERSION=$(echo "$VERSION" | sed -E 's/(\.debian|\.ubuntu|\.fedora|\.arch|\.opensuse)//g')

  # Capture commit hash after checkout
  local _commit
  _commit=$(git rev-parse HEAD)

  echo -e "   ${BOLD}VERSION:${NC} $VERSION"
  echo -e "   ${BOLD}COMMIT :${NC} $_commit"

  # Cleanup repository metadata
  rm -rf .git
  find . -name .gitignore -print0 | xargs -0 rm -f

  cd "$ROOT_DIR"

  # Skip if already exists
  if compgen -G "$DEST_DIR/$PRGNAM-$VERSION.tar.lz" > /dev/null; then
    echo -e "${YELLOW}⏩ Skipping ${PRGNAM} (already exists)${NC}"
    return
  fi

  mv "$GITDIR" "$PRGNAM-$VERSION"
  tar --lzip -cvhf "$PRGNAM-$VERSION.tar.lz" "$PRGNAM-$VERSION"
  rm -rf "$PRGNAM-$VERSION"
  mv -f "$PRGNAM-$VERSION.tar.lz" "$DEST_DIR"

  echo -e "${GREEN}✅ Created:${NC} $DEST_DIR/$PRGNAM-$VERSION.tar.lz"
}

# -------------------------------
# Handle category processing
# -------------------------------
process_category() {
  local CATEGORY=$1
  local FILTER=$2
  local -n REPOS=$3

  echo -e "${BOLD}=== Processing ${CATEGORY^} ===${NC}"

  for PRGNAM in "${!REPOS[@]}"; do
    if [[ -n "$FILTER" && "$PRGNAM" != "$FILTER" ]]; then
      continue
    fi
    process_repo "$PRGNAM" "${REPOS[$PRGNAM]}"
  done
}

# -------------------------------
# Main Logic
# -------------------------------
ARG=$1

if [[ -z "$ARG" ]]; then
  process_category "core components" "" CORE_REPOS
  process_category "applications" "" APPS_REPOS
  process_category "dependencies" "" EXTRA_REPOS
else
  IFS=':' read -r CATEGORY FILTER <<< "$ARG"
  case "$CATEGORY" in
    core) process_category "core components" "$FILTER" CORE_REPOS ;;
    apps|applications) process_category "applications" "$FILTER" APPS_REPOS ;;
    extra|dependencies) process_category "dependencies" "$FILTER" EXTRA_REPOS ;;
    *)
      echo -e "${RED}❌ Unknown category:${NC} $CATEGORY"
      echo "Usage: $0 [core|apps|extra][:optional-filter]"
      exit 1
      ;;
  esac
fi

echo -e "\n${GREEN}🎉 All requested repositories processed.${NC}"
echo -e "   ${BOLD}Output:${NC} $DEST_DIR"

