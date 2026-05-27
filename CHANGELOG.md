# Changelog

본 프로젝트의 모든 주요 변경은 이 파일에 기록됩니다.

형식은 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) 를 따르며,
버전 체계는 [Semantic Versioning](https://semver.org/spec/v2.0.0.html) 을 따릅니다.

## [Unreleased]

## [0.3.0] - 2026-05-27

VERIFICATION (v0.2.1) 에서 가장 큰 영향으로 식별된 **Helper API 영역 스코핑 부재** 를 해소하고, 설치 UX(--uninstall/--dry-run) 와 버전 가시화를 함께 묶은 minor 릴리스. **Backward-compatible** — 기존 spec/flow 코드 그대로 동작.

### Added
- **Helper 7종에 `within?: Locator` 옵션** — `FormHelper`, `SelectHelper`, `TableHelper`, `NavigationHelper`, `CheckboxHelper`, `RadioGroupHelper`, `FileUploadHelper` 의 메서드들이 마지막 인자로 `opts?: { within?: Locator }` 를 받음. 미지정 시 기존과 동일하게 page 전역 검색
- `install.sh` / `install.ps1` 에 **`--uninstall`** 옵션 — `$SKILLS_DIR/$SKILL_NAME` 만 삭제, 부모 디렉터리 보존 (다른 스킬 영향 없음)
- `install.sh` / `install.ps1` 에 **`--dry-run`** 옵션 — tarball 다운로드 + 추출까지 진행 후 *복사 없이* 파일 목록 요약 출력 (네트워크 필요)
- `SKILL.md` frontmatter에 **`version: 0.3.0`** 필드 신규
- install 출력에 "**Done. 설치된 버전: vX.Y.Z**" 라인 — frontmatter에서 추출
- `README.md` 에 "**설치된 버전 확인 방법**" 안내 (`grep` / `Select-String` 두 명령)
- `references/helper-templates.md` 에 **"영역 스코프 옵션 (within)"** 섹션 — 적용 표 + 패턴 + 사용 예
- `references/selector-priority.md` 의 "영역 스코핑" 섹션에 **Helper `within` 옵션 참조** 추가
- `VERIFICATION.md` 에 **"Helper 8-coverage walkthrough (v0.3.0)"** 섹션 — 8 Helper 동작 검증 + per-helper 표 + 발견 사항

### Changed
- `install.sh` / `install.ps1` 헤더 Usage 섹션이 새 옵션 2가지(--uninstall, --dry-run) 반영
- `README.md` 설치 옵션 표가 5행으로 확장

### Notes
- **within 제외 Helper**: `DialogHelper` (모달 자체가 영역), `ToastHelper` (전역이 자연), `NavigationHelper.expectUrlMatches` (URL은 page 상태)
- **SelectHelper × native `<select>` 한계** — Helper API가 ARIA combobox 패턴 전제. native select 사용 프로젝트는 Helper fork 필요. v0.4.x 후보로 식별 (VERIFICATION 참조)

## [0.2.1] - 2026-05-27

v0.2.0 통합 검증([VERIFICATION.md](./VERIFICATION.md))에서 발견한 3가지 문서·설정 정정 + 벤더 중립성 마무리 작업을 묶은 patch 릴리스. **기능 변경 없음** (backward-compatible).

### Fixed
- `references/selector-priority.md` 1순위 섹션에 **`getByRole(name)` substring 매칭 함정** 가이드 추가 — RegExp `/^X$/` / `exact: true` / 영역 스코핑 3가지 회피 방법 명시
- `references/phase-1-setup.md` 4.3 `AGENTS.md` 등록 절차에 **marker block 패턴** 명시 — `<!-- BEGIN:e2e-flow-skill --> ... <!-- END --> ` 로 감싸 멱등 보장 + 다른 도구 marker block과 충돌 회피
- `assets/templates/playwright.config.ts.tmpl` 의 `trace` 옵션을 `'on-first-retry'` → `'retain-on-failure'` 로 변경 — 첫 실패에도 `trace.zip` 보존, Self-Healer 분석 정확도 향상

### Changed
- GitHub repository metadata 벤더 중립화 — description과 topics에서 `claude-code` / `claude-skill` 제거, `ai-skill` / `vrt` 추가. Wiki 비활성화 + Discussions 활성화
- `README.md` 에 **호스트 도구 호환성** 섹션 추가 — Claude Code / Cursor / Cline / Codex / Gemini CLI 의 스킬 인식 위치, 자동 파이프라인 검증 여부, 설치 명령을 표로 명시
- `install.sh` / `install.ps1` 헤더 주석에 디폴트 경로 `~/.claude/skills/` 가 Claude Code 표준이라는 이유 + `--skill-dir` / `-SkillDir` 안내 강화

### Verified
- **Integration verification (Phase 1-3) 완료** — 빈 Next.js 16 + React 19 + Playwright 1.60 환경에서 시뮬레이션 워크스루. install.sh 정상 동작, 자가 복구 4분류 중 3종(UI_CHANGE / TEST_BUG / ENV_ISSUE) 검증, ENV_ISSUE 안전 가드 통과. 자세한 결과·발견 사항·다음 마일스톤 후보는 [VERIFICATION.md](./VERIFICATION.md) 참조

## [0.2.0] - 2026-05-27

### Added
- `CheckboxHelper` — `check` / `uncheck` / `toggle` / `expectChecked` / `checkMultiple` (Tier A)
- `RadioGroupHelper` — `selectByLabel` / `expectSelected` (Tier A)
- `FileUploadHelper` — `selectFiles` / `expectUploadedFile` / `expectFileCount` / `removeFile` (Tier A)
- 자연어→코드 매핑 6 라인 (`SKILL.md` + `self-healer.md` 서브에이전트 프롬프트 동시 갱신)
- `CHANGELOG.md` 도입 (Keep a Changelog 형식)

### Changed
- `README.md` Helper 표를 6종에서 9종으로 갱신
- `fixtures.ts.tmpl` 의 `Helpers` 인터페이스와 `test.extend` 에 신규 3종 등록
- `references/phase-1-setup.md` 의 생성 파일 표와 Helper 카탈로그 확장
- `references/helper-templates.md` 의 "Helper 확장 원칙" 회고 라인을 v0.2.0 반영으로 갱신
- `references/playwright-fixtures.md` 의 타입 확장 패턴 섹션에 v0.2.0 추가 사실 메모

## [0.1.0] - 2026-05-26

### Added
- 4단계 파이프라인 스킬 (인프라 셋업 / 테스트 생성 / 자가 복구 / VRT·CI 확장)
- 6개 Helper (Dialog, Form, Select, Table, Navigation, Toast)
- Codebase Analyzer 서브에이전트 (Phase 1 진입 1회)
- Self-Healer 서브에이전트 (Phase 3 루프, 4분류 자가 복구: UI_CHANGE / TEST_BUG / APP_BUG / ENV_ISSUE)
- Selector 우선순위 규칙 (ARIA role → label → data-slot) + 영역 스코핑
- Dynamic Shard CI 워크플로우 템플릿 (테스트 개수에 비례한 자동 병렬화)
- 설치 스크립트 `install.sh` (Linux/macOS/WSL/Git Bash) 와 `install.ps1` (Windows PowerShell)
- 3가지 설치 방법 안내: curl|bash, irm|iex, `npx skills add`
- `CONTRIBUTING.md` (단일 출처 원칙 + 새 Helper 추가 체크리스트)

### Changed
- 벤더 종속성 표기 정확화 — *자동 파이프라인은 Claude Code에서 검증되었지만, Helper·Selector 규칙·specs/flows 구조·CI 워크플로우 등 콘셉트와 산출물은 벤더 중립* 비대칭을 README와 install 스크립트에 일관 반영

[Unreleased]: https://github.com/CaesiumY/e2e-flow-skill/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/CaesiumY/e2e-flow-skill/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/CaesiumY/e2e-flow-skill/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/CaesiumY/e2e-flow-skill/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/CaesiumY/e2e-flow-skill/releases/tag/v0.1.0
