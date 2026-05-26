# Changelog

본 프로젝트의 모든 주요 변경은 이 파일에 기록됩니다.

형식은 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) 를 따르며,
버전 체계는 [Semantic Versioning](https://semver.org/spec/v2.0.0.html) 을 따릅니다.

## [Unreleased]

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

[Unreleased]: https://github.com/CaesiumY/e2e-flow-skill/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/CaesiumY/e2e-flow-skill/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/CaesiumY/e2e-flow-skill/releases/tag/v0.1.0
