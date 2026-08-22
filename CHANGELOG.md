# Changelog

본 프로젝트의 모든 주요 변경은 이 파일에 기록됩니다.

형식은 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) 를 따르며,
버전 체계는 [Semantic Versioning](https://semver.org/spec/v2.0.0.html) 을 따릅니다.

## [Unreleased]

## [0.5.0] - 2026-08-23

**티어링 기반 CI 실행 예산** minor 릴리스. Phase 4.2를 "트리거 4지선다"에서 **"실행 예산 설계"** 로 승격하고, CI 워크플로우가 실제로 통과할 수 없던 결함들을 함께 해소했다. **Backward-compatible** — 기존 spec/flow 코드는 그대로 동작하며, 이미 생성된 워크플로우 파일도 자동으로 바뀌지 않는다 (아래 마이그레이션 참조).

### Added
- **테스트 태그 규약** (`SKILL.md` 신설 절, 단일 출처) — `@smoke`(도메인당 1개, 전체 5개 이하) / `@critical`(결제·인증·주문·권한·삭제) / 무태그(일반 회귀) / `@vrt`(CI 전 티어에서 제외). Playwright 1.42+ 의 `{ tag: [...] }` 옵션 사용, 미만 버전은 제목 임베드로 폴백
- **6티어 CI 실행 예산** (`playwright-e2e.yml.tmpl` 신규) — `skip`/`smoke`/`scoped`/`critical`/`full`/`nightly`. 티어별로 shard 밀도·상한·`--project`·`timeout-minutes` 를 다르게 잡는다. smoke 는 shard 1 고정(job 오버헤드 > 실행 시간), nightly 는 밀도 40·상한 3(시간 무관, 비용 우선)으로 **정반대 방향** 최적화
- **`e2e:full` / `e2e:skip` 라벨 체계** — 명시적 라벨이 암묵 판정(draft·경로)보다 우선. 라벨 판정은 `github.event.pull_request.labels.*.name`(현재 상태)로 하고, `,` 로 감싼 정확 일치로 비교 (`e2e:full-stack` 오매치 차단)
- **경로 기반 자동 skip** — `gh api .../pulls/{n}/files` 로 변경 파일을 받아 `{{SKIP_PATHS_REGEX}}` 와 대조. API 실패 시 실행하는 쪽으로 폴백하되 `::warning::` 을 남겨 기능이 조용히 무력화되지 않게 함
- **`E2E Gate` job** — shard 개수가 동적이라 개별 job 을 required check 로 걸 수 없는 문제 해소. branch protection 에 이 이름 하나만 등록한다. `"skipped = 성공"` 은 tier=skip 또는 total=0 일 때만 허용
- **0-매칭 자동 승격** — `@smoke` 가 0개 매칭되면 `full` 로 승격 + 경고. "아무것도 안 돌았는데 초록불"을 막는 안전장치
- **도메인 스코프 실행** (선택 기능, `ci-scope.example.json.tmpl` 신규) — `e2e/ci-scope.json` 이 있을 때만 동작. PR 기본 티어를 *넓히는* 방향이며 `e2e:full` 은 절대 좁히지 않는다. `always` 경로 변경·0 매칭은 전부 넓은 쪽으로 폴백
- **Playwright 브라우저 캐시** — 키를 lockfile 해시가 아니라 Playwright 버전으로 잡아 무관한 의존성 변경에 캐시가 깨지지 않게 함. `build` job 이 채우고 모든 shard 가 히트
- `package.json` 스크립트 `test:e2e:smoke` / `test:e2e:critical` — CI 티어와 같은 범위를 로컬에서 재현
- Codebase Analyzer 수집 항목 8번 + `start_command` 필드 — CI 서버 기동 명령의 근거
- `CONTRIBUTING.md` 체크리스트 6번 "CI 워크플로우 템플릿 변경" — 게이팅 회귀가 조용히 통과하는 것을 막는 항목들

### Changed
- **Phase 2 태그 판정 규칙** — 재량이 아니라 키워드 기반 판정 (결제/인증/주문/권한/삭제 → `@critical`). `@smoke` 는 도메인에 아직 없고 정상 경로일 때만, 전체 5개 초과 시 `AskUserQuestion`. 판정 근거를 보고에 1줄 남긴다
- **`workers`** `1` → `2` (`E2E_WORKERS` env 로 오버라이드). `parseInt(... ) || 2` 로 받는다 — `Number('')` 는 0 이 되어 워커 0 이 된다
- **`concurrency` 그룹에 `event_name` 포함** — 기본 브랜치 push 와 schedule 이 같은 그룹을 공유해 서로 큐잉되던 문제. `cancel-in-progress` 는 PR 에서만 true (push·schedule 은 회귀 이력이므로 보존)
- **개수 측정 job 을 `build` 에 흡수** — 별도 job 은 checkout+install(~1분)을 중복하면서 `--list` 10초를 얻는 거래였다. run 당 job 1개 절감
- build artifact 에서 `.next/cache` 제외 (수십~수백 MB)
- `README.md` 요구사항 **Playwright 1.40+ → 1.42+** (`{ tag: [...] }`, `--pass-with-no-tests` 도입 버전)
- Phase 1 Step 3 에 `@playwright/test` 버전 하한 확인 절차 추가
- 예시 spec(`spec.example.ts.tmpl`)에 `@smoke` 부여 — 최소 1개를 보장해 매 PR 전체 승격을 방지
- 야간 VRT job 은 **주석 블록으로만** 제공 — 스냅샷 파일명의 플랫폼 접미사(`-linux.png`) 때문에 로컬 베이스라인은 러너에서 전부 "missing snapshot" 이 되어 매일 실패하는 job 이 된다. Linux 베이스라인 생성 명령을 주석에 안내

### Fixed
- **CI 에서 앱 서버가 기동되지 않던 결함** — `playwright.config.ts` 가 `webServer: CI ? undefined` 였고 워크플로우에도 서버 기동 스텝·`E2E_BASE_URL` 주입이 없어, 전 테스트가 `ERR_CONNECTION_REFUSED` 로 실패하고 `retries: 2` 때문에 3배로 낭비되던 문제. `USE_LOCAL_SERVER` 분기 + `{{START_CMD}}` 도입
- **`{{START_CMD}}` 포트 규칙 명문화** — 프레임워크 기본 포트를 믿으면 안 된다 (Vite 는 dev 5173 / `preview` 4173). BASE_URL 과 같은 포트에 명시 바인딩하는 표를 `phase-1-setup.md` Step 4 에 단일 출처로 배치
- **라벨 트리거가 후속 push 에 반응하지 않던 문제** — `types: [labeled]` + `github.event.label.name` 조합은 라벨을 붙인 그 순간 1회만 돈다. PR 이벤트 타입 7종을 받고 현재 라벨 상태로 판정하도록 수정
- **개수 측정 스텝이 0매칭에서 exit 1 로 죽던 문제** — `--pass-with-no-tests` 추가. 실행 스텝에도 같은 플래그를 붙여 버전 의존적 동작(`--shard` 유무에 따른 exit code 차이)에 기대지 않게 함
- **변경 파일 목록이 비었을 때 skip 으로 빠지던 문제** — `grep -v` 파이프라인이 빈 입력을 "매치 없음"으로 반환해 `RELEVANT=false` → skip → gate green 으로 흘렀다. 빈 목록을 명시적으로 "관련 있음"으로 처리
- 개수 측정 스텝의 불필요한 `playwright install` 제거 — `--list` 는 브라우저가 필요 없다 (job 당 60~90초)
- shard 개수 상한 도입 — 기존에는 무제한이라 테스트 300개면 러너 20대를 동시 점유했다

### Migration (v0.4.x 에서 올라오는 경우)

이미 `.github/workflows/playwright.yml` 을 생성한 프로젝트만 해당한다. 스킬 업데이트는 기존 파일을 덮어쓰지 않는다.

1. **워크플로우 재생성** — "CI 워크플로우 다시 만들어줘" 로 Phase 4.2 재실행 (기존 파일은 백업 후 교체)
2. **라벨 교체** — `e2e` / `release` → `e2e:full` / `e2e:skip`
   ```bash
   gh label create "e2e:full" --description "이 PR 에서 E2E 전체 스위트 실행" --color 0E8A16
   gh label create "e2e:skip" --description "이 PR 에서 E2E 건너뛰기" --color C5DEF5
   ```
3. **branch protection** — required check 를 `E2E Gate` 로 변경
4. **`playwright.config.ts` 갱신** — `webServer` 가 `CI ? undefined` 형태면 반드시 교체한다 (그대로 두면 CI 에서 전 테스트가 실패한다)
5. **기존 spec 에 태그 부여** — `@smoke` 가 하나도 없으면 매 PR 이 전체 스위트로 승격되어 비용 절감이 없다
6. **`E2E_BASE_URL` 의미 변경 주의** — 이제 이 값이 있으면 "외부 환경을 대상으로 하니 로컬 서버를 띄우지 말라"는 뜻이다. 로컬 포트만 바꾸던 용도로 쓰고 있었다면 config 의 기본값을 고치는 방식으로 옮긴다

### Notes
- 검증: 티어 결정 스크립트를 템플릿에서 추출해 22개 케이스로 단위 검증 (라벨 우선순위, 부분 문자열 오매치, 빈 env, 도메인 스코프 6종). 렌더링 후 YAML 파싱. 상세는 [VERIFICATION.md](./VERIFICATION.md)
- 4분류 체계(UI_CHANGE/TEST_BUG/APP_BUG/ENV_ISSUE)와 Helper 9종은 이번 변경과 무관하게 그대로다

## [0.4.0] - 2026-07-13

**Opus 오케스트레이터 실행 준비 + 서브에이전트 모델 티어링** minor 릴리스. 7차원 병렬 감사(원시 58건 → 적대적 검증 확정 35건)와 6방향 재검증(확정 23건)으로 식별된 개선을 반영. 핵심 방향: 재량 표현을 명시적 판정 규칙으로, 암묵 계약을 검증 게이트로, 서브에이전트를 하위 모델 티어로. **Backward-compatible** — 기존 spec/flow 코드 그대로 동작.

### Added
- **서브에이전트 모델 티어 정책** (`SKILL.md`) — Codebase Analyzer = Explore/`haiku`, Self-Healer = general-purpose/`sonnet`, Phase 1 템플릿 일괄 복사(선택) = general-purpose/`haiku`, 그 외 메인 스레드. model 파라미터 미지원 호스트 폴백(인자 생략 → 메인 모델 상속) 명시
- **Phase 1 검증 게이트** — 미치환 `{{}}` 토큰 grep 0건 + `playwright test --list` ≥ 1 통과 시에만 완료 선언 (기존: 사용자 안내만). 설치 exit code 확인·실패 시 중단 절차 추가
- **Phase 1 부분 재셋업 절차** — Helper 9종 중 일부 누락 시 누락분만 생성하고 기존 `fixtures.ts`는 증분 갱신(비파괴). SKILL.md 라우팅 표에 대응 행 신설
- **Phase 2 정적 검증 게이트 (Step 4.5)** — 생성물의 Helper 메서드 실재 대조 + 트랜스파일 확인, 실패 시 Phase 3 진입 금지 (생성 결함이 자가 복구 예산을 소진하는 문제 차단)
- **Phase 3 Step 0** — 대상 spec 확정(실패 출력 파싱 → 질문 → 전체 실행 폴백) + 패키지 매니저 감지(lockfile 우선순위, 직접 진입 경로 대응)
- **Phase 3 컴파일 에러 사전 필터** — TS 에러/SyntaxError/Cannot find module 은 4분류 대상에서 제외, Self-Healer 디스패치 없이 메인이 직접 수정
- **Self-Healer 응답 형식 검증(Step 4.5) + 오케스트레이터 재검 게이트 3종(Step 5.0)** — 근거-신호 정합성 / edits 안전 범위 / confidence 캘리브레이션. 형식 위반 시 1회 재디스패치 프로토콜
- **Phase 3 다중 실패 정책** — spec별 독립 시도 카운터, 같은 spec 복수 실패는 단일 디스패치로 묶음, 서로 다른 spec은 병렬 디스패치(최대 3) + edits 순차 적용 충돌 가드
- **Phase 3 ↔ Phase 2 재생성 복귀 계약** — 3회 소진 + TEST_BUG 수렴 시 시도 이력·마지막 가설을 인계해 flow 재설계 (단방향 파이프라인 해소)
- **Phase 1→2 시나리오 핸드오프** — 셋업 요청에 동반된 자연어 시나리오를 보관했다가 재입력 없이 Phase 2로 전달
- `NavigationHelper.expectMainVisible()` — 랜드마크 가시성 검증. `flows.example.ts.tmpl` 이 raw Playwright API 대신 이 Helper를 사용하도록 정정 (스킬 자신의 안티패턴 위반 해소)
- CI 템플릿 **`{{TRIGGER_BLOCK}}` / `{{FILTER_CONDITION}}` 치환 도입** — 트리거 4종(모든 PR / 라벨 / 스케줄 / 셋 다) 선택지별 YAML 조각을 짝으로 제공. "모든 PR" 선택 시 filter job 라벨 게이트에 걸려 전부 스킵되던 결함 동시 해소

### Changed
- **Self-Healer 출력 계약 v2** — unified diff 폐지 → YAML 헤더(`classification`/`confidence`/`reasoning`/`edits_count`/`notes_to_user`) + `EDIT` 블록(OLD/NEW 정확 문자열 쌍). Edit 도구와 1:1 대응, `patch: null` 표기 모호성 제거, 적용 절차(OLD 유일성 확인 → Edit) 명문화
- **Self-Healer 패치 대상 규칙** — "Helper 우선 수정" → **"값의 출처 추적"** (호출부 명시 인자에서 온 실패값은 호출부 수정, Helper 기본값·내부 selector 실패만 Helper 수정. 명시 인자가 있는데 기본값만 바꾸는 무효 패치 차단)
- `self-healer.md` 입력을 형식 토큰(`{{SPEC_CONTENT}}` 등, [필수]/[선택] 마커)으로 전환 + 필수 입력 누락 가드. 자연어→코드 매핑 표를 마스터와 동일한 15행으로 완비. 이전 시도 이력(`{{PRIOR_ATTEMPTS}}`) 주입 + 동일 edits 반복 가드
- `SKILL.md` 라우팅 표 v2 — 위→아래 첫 매치 규칙 명시, 부분 재셋업 행, 복합 요청 직렬 실행(셋업→생성→치유). 상태 감지를 신호별 지정 도구로 재작성 (Helper는 개수가 아닌 9종 이름 대조 — "목표 6개" 잔재 제거)
- **시도 정의 통일** — "시도 = 대상 spec 실행 1회, 최초 실행이 시도 1, spec별 최대 3회 실행(edits 적용은 최대 2회 — 시도 3의 제안은 적용하지 않고 보고에 첨부)"
- Phase 3 실행 Bash timeout 600000ms 명시(기존 "기본보다 길게"), `webServer` 자동 기동 인지, ENV_ISSUE 재시도 명령을 감지된 매니저 기준으로 통일
- Phase 1 설치 안내를 패키지 매니저별 명령 표(pnpm/npm/yarn/bun)로 교체 — pnpm 하드코딩 제거. Analyzer 출력 스키마와 기대 출력 1:1 동기화, `base_url_hint`→`{{BASE_URL}}` 자동 연결
- Phase 3 디스패치 시 규칙 전문 재임베드 지시 삭제 — `self-healer.md` 내장 축약본이 단일 출처. `{{HELPER_SIGNATURES}}` 는 스킬 템플릿이 아닌 **프로젝트 실제 `e2e/helpers/*.ts`** 에서 추출
- Phase 2 참조 패턴 선택 규칙(동일 도메인 → 최근 수정 → example 3단계) + 시작 경로 해소 규칙 명시
- Phase 1 Step 5 의 `tsc --noEmit` 은 참고용(비차단)으로 완화 — 기존 앱 코드 타입 에러가 셋업 완료를 막지 않도록

### Fixed
- CI 템플릿 실행 명령 npm 호환 — `{{PACKAGE_MANAGER}} run test:e2e -- ...` 형식으로 통일 (npm에서 카운트 스텝이 빈 값, 실행 스텝이 Unknown command 로 깨지던 문제)
- `playwright.config.ts.tmpl` 의 `webServer.command` 를 `{{PACKAGE_MANAGER}} run dev` 로 수정 (`npm dev` 는 존재하지 않는 명령)
- `helper-templates.md` 9개 코드 블록과 `playwright-fixtures.md` 예시(6개→9개 주입)를 실제 `.tmpl` 과 완전 동기화 — v0.3.0 `within` 시그니처 반영, Self-Healer 카탈로그 오염 해소
- 죽은 치환 토큰(`{{FRAMEWORK}}`, `{{DESIGN_SYSTEM_HINT}}`) 삭제, `{{TRIGGER_BLOCK}}` 죽은 참조 해소, phase-4 요약의 job명(`generate-shards-matrix`)·스케줄 상태를 실제 템플릿과 일치
- Helper "6종/6개" 잔재 표기 전면 정리 (`SKILL.md` 상태 감지, README 트리·각주, CONTRIBUTING 체크리스트)
- `apiMockHandlers` 의 `headers` 필드와 `patternMatch()` 를 `playwright-fixtures.md` 에 문서화 (기능 재발명 방지)
- `selector-priority.md` 에 의도 명시형 Helper 내부 `first()` 사용(`selectFirstOption`)의 예외 명문화

### Notes
- 검증 방법: 다중 에이전트 파이프라인 — 7차원 병렬 감사 → 통합·중복 제거 → 발견사항별 2표 적대적 검증 → 구현 → 6방향 재검증(교차참조 재감사, Opus 실행자 시뮬레이션 워크스루 3종, diff 회귀 리뷰, 앵커 grep) → 확정 결함 수정 → 재검사. 상세는 [VERIFICATION.md](./VERIFICATION.md)
- 4분류 체계(UI_CHANGE/TEST_BUG/APP_BUG/ENV_ISSUE)는 의도적으로 유지 — 컴파일 에러는 5번째 분류가 아니라 사전 필터로 처리 (분류 체계가 6개 문서에 복제돼 있어 파급 최소화)

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

[Unreleased]: https://github.com/CaesiumY/e2e-flow-skill/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/CaesiumY/e2e-flow-skill/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/CaesiumY/e2e-flow-skill/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/CaesiumY/e2e-flow-skill/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/CaesiumY/e2e-flow-skill/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/CaesiumY/e2e-flow-skill/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/CaesiumY/e2e-flow-skill/releases/tag/v0.1.0
