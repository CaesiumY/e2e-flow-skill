# Integration Verification — v0.2.0 baseline

본 문서는 README가 약속한 4단계 파이프라인이 실제로 동작하는지 본인이 워크스루해 증명한 결과 보고이다. 워크스루는 **시뮬레이션** 형태(*fresh Claude Code 세션의 `/e2e-flow` 자동 트리거가 아닌*, 본 세션이 SKILL.md/references/ 절차를 직접 따라가는 형태)로 진행되었으며, 한계는 [Out of Scope](#검증되지-않은-항목-out-of-scope) 섹션에 명시한다.

## 환경

| 항목 | 값 |
|---|---|
| 날짜 | 2026-05-27 |
| 검증자 | 본 세션 (시뮬레이션) |
| OS | Windows 11 x64 |
| Node | v24.11.0 |
| pnpm | 10.33.0 |
| Next.js | 16.2.6 (App Router, src dir) |
| React | 19.2.4 |
| Playwright | 1.60.0 |
| Chromium | playwright 1.60.0 번들 |
| e2e-flow commit | `a4eb3ee` (v0.2.0 + docs/metadata 정정) |
| 검증 환경 | `C:\Users\mn065\Desktop\projects\verify-target\` (e2e-flow-skill 형제 디렉터리) |

## 워크스루 결과 요약

| Phase | 결과 | 비고 |
|---|---|---|
| **Phase 1 — 인프라 셋업** | ✅ 통과 | `install.sh` 정상 동작, 산출물 14항목 모두 생성 |
| **Phase 2 — 테스트 생성** | ✅ 통과 (1회 자가복구 후) | happy path가 즉시 TEST_BUG 자연 발생 |
| **Phase 3 — 자가 복구** | ✅ 통과 | 3 시나리오 모두 의도된 분류 도달 |
| **Phase 4 — 확장** | ⏭ 시각 점검만 | Plan 범위 외 |

---

## Phase 1 결과

### 산출물 체크리스트

| 항목 | 결과 |
|---|---|
| `playwright.config.ts` (BASE_URL/PACKAGE_MANAGER 치환 확인) | ✅ |
| `e2e/helpers/` 9종 Helper | ✅ |
| `e2e/fixtures.ts` (Helper 9종 자동 주입) | ✅ |
| `e2e/mocks/apiMockHandlers.ts` | ✅ |
| `e2e/tests/example/specs/landing.spec.ts` | ✅ |
| `e2e/tests/example/flows/landing-flows.ts` | ✅ |
| `e2e/shared/sequences/.gitkeep` | ✅ |
| `docs/ai/skills/e2e-flow-generator.md` | ✅ |
| `AGENTS.md` (e2e-flow-skill marker block 추가) | ✅ |
| `package.json` 스크립트 4개 (`test:e2e`, `test:vrt`, `test:vrt-update`, `test:e2e:ui`) | ✅ |
| `.gitignore` Playwright 항목 추가 | ✅ |
| `@playwright/test` 1.60.0 설치 | ✅ |
| Chromium 브라우저 설치 | ✅ |
| `pnpm exec playwright test --list` 정상 (2 tests 인식) | ✅ |

**총 14 ✓ / 0 ❌**

### Codebase Analyzer 시뮬레이션 결과

빈 `create-next-app` 환경 → *디자인 시스템 미확인* → 사용자 선택지 (shadcn / MUI / 사내 / 기타) 제시 가정 → **기타** 선택 가정. Plan 함정 #1 (디자인 시스템 미확인 케이스) 정상 처리.

### 발견 (Phase 1)

1. **`--agents-md` create-next-app default** (함정 #5 확인): AGENTS.md가 `<!-- BEGIN:nextjs-agent-rules --> ... <!-- END --> ` marker block으로 자동 생성됨. e2e-flow Phase 1 절차서의 4.3은 *단순 append* 방식이라 *idempotent 검증* 부재 → 본 워크스루는 *별도 marker block* (`<!-- BEGIN:e2e-flow-skill --> ... <!-- END:e2e-flow-skill -->`)으로 추가해 충돌·중복 회피. **개선 후보**: 절차서 4.3에 marker block 패턴 명시.
2. **`CLAUDE.md` 자동 생성** (11 bytes 빈 파일): create-next-app default. e2e-flow가 트리거 기반이라 머지 불필요지만, 호스트 컨벤션의 한 데이터.
3. **Next.js 16.2.6 + React 19.2.4** 호환성: e2e-flow templates가 별 문제 없이 동작. Next 16 specific issues 없음.

---

## Phase 2 결과

### 입력 자연어

> "/create-agent 페이지에서 이름·설명 입력하고 저장 누르고, 생성 확인 모달에서 생성 누르고, 성공 토스트가 뜨는지 확인하는 테스트 만들어줘"

### 생성된 파일

- `e2e/tests/create-agent/specs/create.spec.ts`
- `e2e/tests/create-agent/flows/create-flows.ts`

생성된 spec 코드(요약):
```ts
test('정상 생성 플로우', async ({ page, form, dialog, toast }) => {
  await page.goto('/create-agent');
  await 에이전트_생성_플로우({ page, form, dialog, toast });
});
```

flow 코드 — 자연어→코드 매핑 표 그대로 적용:
- "이름·설명 입력하고" → `form.fillFields({ '이름': ..., '설명': ... })`
- "저장 누르고" → `form.submit('저장')` *(→ 자연 발생 TEST_BUG, 패치 후 `/^저장$/`)*
- "생성 확인 모달에서 생성 누르고" → `dialog.waitForOpen()` + `dialog.clickConfirm('생성')`
- "성공 토스트가 뜨는지" → `toast.expectSuccess()`

### 평가

- Selector 우선순위 준수: 모두 1순위 `getByRole` + 2순위 `getByLabel`
- 자연어→코드 매핑이 직관적으로 동작

### 발견 (Phase 2)

- **Happy path가 즉시 strict mode violation으로 실패** — 시연 페이지의 2개 `저장` 버튼 (header + form) 때문. **FormHelper에 영역 스코프 옵션이 없음** → spec/flow 작성자가 *영역 스코프 의무* 를 짊어짐. 본 워크스루는 `RegExp /^저장$/` exact 매칭으로 우회. *Plan Scenario B의 자연 발생 케이스* — Phase 3 자가복구 루프가 자동 처리.
- **`getByRole(name: '저장')` 의 substring 매칭 함정**: Playwright의 기본 매칭이 substring이라 "페이지 헤더 저장"도 매칭됨. README의 Selector 우선순위 섹션에 *exact 매칭 가이드 부재*.

---

## Phase 3 결과 — Per-attempt 표

| # | Scenario | Classification | Confidence | Patch | Result | 시간 |
|---|---|---|---|---|---|---|
| 1.1 | Happy path (자연 발생 TEST_BUG) | **TEST_BUG** | 0.85 | `form.submit('저장')` → `form.submit(/^저장$/)` | ❌ strict mode violation | 769ms |
| 1.2 | Same (after patch) | — | — | — | ✅ 통과 | 640ms |
| 2.1 | **A — UI_CHANGE** (form 버튼 텍스트 `저장`→`등록`) | **UI_CHANGE** | 0.85 | flow `/^저장$/` → `/^등록$/` | ❌ Timeout (matcher 0개) | 10s |
| 2.2 | Same (after patch) | — | — | — | ✅ 통과 | 568ms |
| 3.1 | **C — ENV_ISSUE** (`CI=1`로 webServer 비활성화) | **ENV_ISSUE** | 0.95 | **null (수정 금지)** | ❌ net::ERR_CONNECTION_REFUSED + retry 2회 모두 실패 → **안전 가드 통과** | ~30s |

### Scenario별 발견

**Scenario 1 (자연 발생 TEST_BUG)**:
- happy path 작성만으로 즉시 발생. Plan 시나리오가 의도한 *별도 트리거*가 아니라 *Phase 2 출력 그 자체*가 트리거. Plan 메타 발견.
- Healer 시뮬레이션 분류 적중 ✅

**Scenario 2 (UI_CHANGE)**:
- 시연 페이지 form 버튼 텍스트 변경 → flow의 `/^저장$/` selector 매칭 0개 → TimeoutError
- Healer가 screenshot 분석 후 `/^등록$/` 패치 제안 ✅
- **trace.zip 미생성 발견**: `trace: 'on-first-retry'` 설정 때문에 첫 실패엔 PNG만. 실제 Healer 서브에이전트에선 trace 부재가 분류 정확도에 영향 줄 수 있음.

**Scenario 3 (ENV_ISSUE)**:
- 안전 가드 통과: **코드 수정 없음**, retry 2회 모두 실패해도 패치 적용 안 함 ✅
- `net::ERR_CONNECTION_REFUSED` 메시지가 명확해 분류 confidence 0.95

---

## 발견 사항 정리 — 다음 마일스톤 후보

### v0.2.1 patch 후보 (작은 정정)

1. **README Selector 우선순위 섹션에 "exact 매칭 가이드" 추가** — `getByRole(name)` 의 substring 매칭 함정 명시 + `RegExp` 또는 `{ exact: true }` 사용 안내
2. **Phase 1 절차서 4.3 (`AGENTS.md` 갱신)에 marker block 패턴 명시** — `<!-- BEGIN:e2e-flow-skill --> ... <!-- END --> ` 형태로 감싸기. 단순 append 대비 idempotent
3. **`playwright.config.ts.tmpl` 의 `trace` 옵션 검토** — `'on-first-retry'` → `'on'` 또는 *최소 첫 실패에 trace 보장* 옵션 노출

### v0.3.0 minor 후보 (Helper API 개선)

4. **FormHelper에 영역 스코프 옵션 도입** — 예: `submit(label, { within?: Locator })`. 영역 스코프 의무를 Helper가 흡수. Dialog/Table/Navigation Helper도 동일한 옵션 검토
5. **Helper 9종 *각각의 실제 동작 검증*** — 본 워크스루는 FormHelper/DialogHelper/ToastHelper만 검증. Select/Table/Navigation/Checkbox/RadioGroup/FileUpload는 시연 환경 없음. 시연 페이지 확장 또는 별도 검증 케이스 필요

### v0.4.0+ 후보 (큰 변경)

6. **fresh Claude Code 세션의 `/e2e-flow` 자동 트리거 검증** — 본 워크스루는 시뮬레이션. 실제 트리거 정확도·context loading·서브에이전트 dispatch 정확도는 별도 검증
7. **APP_BUG 분류 시나리오 설계** — 의도적 앱 결함 트리거 방법 마련

---

## 검증되지 않은 항목 (Out of Scope)

다음 항목은 본 워크스루의 범위 밖. 향후 마일스톤에서 다룸:

- **APP_BUG 분류** — 의도적 앱 결함 트리거 시나리오 미설계. Plan 합의 (v0.3.0 후보)
- **`confidence < 0.5` 분기** — 의도적 모호 시나리오 작성 어려움. 별도 probe 필요
- **Phase 4 CI 실제 실행** — GitHub Actions 분 소비 부담. 템플릿 시각 점검으로 갈음
- **Mobile project (chromium-mobile)** — `playwright.config.ts.tmpl`의 projects가 주석 처리 상태. 모바일 분기 검증 미수행
- **fresh Claude Code 세션의 `/e2e-flow` 자동 트리거** — 본 워크스루는 시뮬레이션. SKILL.md description 매칭, 자동 서브에이전트 dispatch 정확도 미검증
- **Helper 9종 중 6종** — Select/Table/Navigation/Checkbox/RadioGroup/FileUpload는 시연 페이지에 등장 안 함. 별도 검증 필요

---

## 결론

**README가 약속한 4단계 파이프라인의 핵심 흐름이 시뮬레이션 환경에서 검증되었음.** 다음 사항을 증명:

- ✅ **install.sh 정상 동작** — verify-target에 26개 스킬 파일 정상 설치
- ✅ **Phase 1 산출물 14항목 모두 생성** — Codebase Analyzer 시뮬레이션 결과를 메인 스레드가 templates 복사·치환으로 처리
- ✅ **자연어 → spec/flow 변환** — Phase 2 자연어→코드 매핑 표가 직관적으로 동작
- ✅ **자가 복구 4분류 동작** — UI_CHANGE / TEST_BUG / ENV_ISSUE 검증 (APP_BUG 보류)
- ✅ **ENV_ISSUE 안전 가드 통과** — 코드 수정 없이 보고만, 의도된 동작

**개선 우선순위 발견**:

- ⚠️ **FormHelper에 영역 스코프 부재** → spec 작성 부담 → *v0.3.0 minor* 후보
- ⚠️ **`trace: 'on-first-retry'` 의 첫 실패 분석 한계** → *v0.2.1 patch* 후보
- ⚠️ **README의 substring 매칭 함정 가이드 부재** → *v0.2.1 patch* 후보
- ⚠️ **AGENTS.md marker block 패턴 부재** → *v0.2.1 patch* 후보

본 워크스루는 *시뮬레이션*이라 fresh Claude Code 세션의 자동 트리거 흐름은 미검증. v0.4.0+ 마일스톤에서 다룰 예정.
