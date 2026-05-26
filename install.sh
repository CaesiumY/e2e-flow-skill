#!/usr/bin/env bash
# e2e-flow-skill installer (Linux / macOS / WSL / Git Bash)
#
# Installs the e2e-flow Claude Code skill. This is a Claude Code-specific
# workflow skill — it does not provide adapters for other AI tools.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/CaesiumY/e2e-flow-skill/main/install.sh | bash
#   bash install.sh --target=project          # install into ./.claude/skills/ instead of ~/.claude/skills/
#   bash install.sh --ref=v1.2.3              # pin to a tag/branch (default: main)
#   bash install.sh --skill-dir=/custom/path  # override install destination
#
# The skill is trigger-based: Claude Code invokes it automatically when your
# prompt matches the description (e.g. "Playwright 셋업", "E2E 테스트
# 추가", "테스트 깨졌어 고쳐줘"). No CLAUDE.md merge needed.

set -euo pipefail

REPO="CaesiumY/e2e-flow-skill"
SKILL_NAME="e2e-flow"
REF="main"
TARGET="global"
CUSTOM_DIR=""

for arg in "$@"; do
  case "$arg" in
    --target=project)  TARGET="project" ;;
    --target=global)   TARGET="global" ;;
    --ref=*)           REF="${arg#--ref=}" ;;
    --skill-dir=*)     CUSTOM_DIR="${arg#--skill-dir=}" ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# //; s/^#$//'
      exit 0
      ;;
    *)
      echo "unknown arg: $arg" >&2
      exit 2
      ;;
  esac
done

# 설치 경로 결정 우선순위: --skill-dir > --target=project > --target=global(기본)
if [ -n "$CUSTOM_DIR" ]; then
  SKILLS_DIR="$CUSTOM_DIR"
elif [ "$TARGET" = "project" ]; then
  SKILLS_DIR="$PWD/.claude/skills"
else
  SKILLS_DIR="${HOME}/.claude/skills"
fi

WORK_DIR="$(mktemp -d -t e2e-flow-skill.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

TARBALL_URL="https://codeload.github.com/${REPO}/tar.gz/${REF}"
echo "↓ downloading ${REPO}@${REF}"
curl -fsSL "$TARBALL_URL" -o "$WORK_DIR/repo.tar.gz"
tar -xzf "$WORK_DIR/repo.tar.gz" -C "$WORK_DIR"

EXTRACTED_DIR="$(find "$WORK_DIR" -maxdepth 1 -type d -name 'e2e-flow-skill-*' | head -n1)"
SRC="$EXTRACTED_DIR/skills/$SKILL_NAME"
if [ -z "$EXTRACTED_DIR" ] || [ ! -d "$SRC" ]; then
  echo "ERROR: skills/$SKILL_NAME not found in tarball" >&2
  exit 1
fi

mkdir -p "$SKILLS_DIR"
DEST="$SKILLS_DIR/$SKILL_NAME"
if [ -d "$DEST" ]; then
  echo "↺ existing install detected at $DEST — replacing"
  rm -rf "$DEST"
fi
cp -r "$SRC" "$DEST"
echo "✔ installed $SKILL_NAME -> $DEST/"

cat <<EOF

Done.

Trigger phrases (자연어로 호출하면 자동 발동):
  - "Playwright 셋업해줘", "E2E 테스트 추가해줘"
  - "이 페이지 테스트 만들어줘"
  - "테스트 깨졌어 고쳐줘"
  - "VRT 붙여줘", "E2E CI 워크플로우 추가해줘"

스킬 위치: $DEST/
SKILL.md:  $DEST/SKILL.md
EOF
