#!/usr/bin/env bash
# e2e-flow-skill installer (Linux / macOS / WSL / Git Bash)
#
# Installs the e2e-flow skill. The automated 4-phase pipeline (subagent
# dispatch + tool calls) is verified on Claude Code. The skill content inside
# skills/e2e-flow/ (helpers, selector rules, templates, CI workflow) is
# reusable in any AI coding agent or as plain reference material.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/CaesiumY/e2e-flow-skill/main/install.sh | bash
#   bash install.sh --target=project          # install into ./.claude/skills/ instead of ~/.claude/skills/
#   bash install.sh --ref=v1.2.3              # pin to a tag/branch (default: main)
#   bash install.sh --skill-dir=/custom/path  # override install destination
#   bash install.sh --dry-run                 # download + list what would be copied, no install (requires network)
#   bash install.sh --uninstall               # remove $SKILLS_DIR/$SKILL_NAME only (parent preserved). no download
#
# Default location: ~/.claude/skills/ (Claude Code's standard skills directory,
# the host where the auto-pipeline is verified). For other AI coding agents
# (Cursor, Cline, Codex, Gemini CLI), use --skill-dir=<their-skills-path>.
# See README.md > "호스트 도구 호환성" for the per-tool path mapping.
#
# The skill is trigger-based: the host AI tool invokes it automatically when
# your prompt matches the SKILL.md description (e.g. "Playwright 셋업",
# "E2E 테스트 추가", "테스트 깨졌어 고쳐줘"). No CLAUDE.md merge needed.

set -euo pipefail

REPO="CaesiumY/e2e-flow-skill"
SKILL_NAME="e2e-flow"
REF="main"
TARGET="global"
CUSTOM_DIR=""
UNINSTALL=0
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --target=project)  TARGET="project" ;;
    --target=global)   TARGET="global" ;;
    --ref=*)           REF="${arg#--ref=}" ;;
    --skill-dir=*)     CUSTOM_DIR="${arg#--skill-dir=}" ;;
    --uninstall)       UNINSTALL=1 ;;
    --dry-run)         DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,26p' "$0" | sed 's/^# //; s/^#$//'
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
DEST="$SKILLS_DIR/$SKILL_NAME"

# ---------- Uninstall mode (no download) ----------
if [ "$UNINSTALL" = "1" ]; then
  if [ ! -d "$DEST" ]; then
    echo "Nothing to uninstall: $DEST not found"
    exit 0
  fi
  echo "↺ removing $DEST"
  rm -rf "$DEST"
  echo "✔ uninstalled $SKILL_NAME from $SKILLS_DIR/"
  echo ""
  echo "Note: parent directory $SKILLS_DIR/ preserved (other skills untouched)."
  exit 0
fi

# ---------- Download + extract (needed for both install and dry-run) ----------
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

# ---------- Dry-run: list files and exit ----------
if [ "$DRY_RUN" = "1" ]; then
  echo ""
  echo "=== Dry-run: files that would be installed ==="
  echo "Destination: $DEST/"
  echo ""
  (cd "$SRC" && find . -type f) | sed 's|^\./|  |'
  COUNT="$( (cd "$SRC" && find . -type f) | wc -l )"
  echo ""
  echo "총 $COUNT 개 파일이 $DEST/ 에 복사됩니다."
  echo "(실제 설치는 --dry-run 옵션 없이 다시 실행)"
  exit 0
fi

# ---------- Actual install ----------
mkdir -p "$SKILLS_DIR"
if [ -d "$DEST" ]; then
  echo "↺ existing install detected at $DEST — replacing"
  rm -rf "$DEST"
fi
cp -r "$SRC" "$DEST"
echo "✔ installed $SKILL_NAME -> $DEST/"

# SKILL.md frontmatter에서 version 추출 (없으면 unknown 표시)
INSTALLED_VERSION="$(grep -m1 '^version:' "$DEST/SKILL.md" 2>/dev/null | awk '{print $2}' || true)"
if [ -z "$INSTALLED_VERSION" ]; then
  INSTALLED_VERSION="unknown"
fi

cat <<EOF

Done. 설치된 버전: v${INSTALLED_VERSION}

Trigger phrases (자연어로 호출하면 자동 발동):
  - "Playwright 셋업해줘", "E2E 테스트 추가해줘"
  - "이 페이지 테스트 만들어줘"
  - "테스트 깨졌어 고쳐줘"
  - "VRT 붙여줘", "E2E CI 워크플로우 추가해줘"

스킬 위치: $DEST/
SKILL.md:  $DEST/SKILL.md
버전 재확인: grep '^version:' $DEST/SKILL.md
EOF
