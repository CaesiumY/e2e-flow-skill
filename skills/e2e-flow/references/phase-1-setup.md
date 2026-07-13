# Phase 1 — 인프라 셋업 절차

프로젝트에 `playwright.config.*` 가 없을 때 실행하는 셋업 페이즈. **Codebase Analyzer 서브에이전트**를 한 번 디스패치한 뒤, 결과에 따라 메인 스레드에서 템플릿을 복사·치환한다.

---

## Step 1. Codebase Analyzer 디스패치

`assets/prompts/codebase-analyzer.md` 의 프롬프트로 `Explore` 서브에이전트를 호출한다.

```text
Agent({
  description: "Frontend codebase analysis for E2E setup",
  subagent_type: "Explore",
  model: "haiku",
  prompt: <assets/prompts/codebase-analyzer.md 내용을 그대로 사용>
})
```

> `model` 인자를 지원하지 않는 호스트에서는 생략한다 — 메인 모델을 상속해 동작은 동일하고 비용만 증가한다(A2).

**기대 출력** (analyzer YAML 스키마와 1:1, 200단어 이내):

| YAML 필드 | 내용 |
|---|---|
| `framework` | Next.js (App Router) / Next.js (Pages) / Vite / CRA / Remix / Nuxt / 기타 |
| `package_manager` | pnpm / npm / yarn / bun |
| `design_system` | shadcn/ui / MUI / Chakra / Mantine / Ant Design / 사내 / 미확인 |
| `routing` | 파일 기반 / React Router / 기타 |
| `existing_tests.unit` | jest / vitest / 없음 |
| `existing_tests.e2e` | playwright / cypress / 없음 |
| `env_files` | 발견된 `.env*` 파일 목록 |
| `dev_command` | `scripts.dev` 또는 `scripts.start` |
| `base_url_hint` | 포트에서 추론한 URL (예: `http://localhost:3000`) |
| `notes` | 메인 스레드에 알려줄 특이사항 한두 줄 |

**출력 형식 검증**: 위 YAML 필드가 전부 존재하는지 확인한다. 누락 필드가 있으면 동일 프롬프트로 **1회만** 재디스패치하고, 그래도 누락이면 해당 값을 "미확인"으로 두고 Step 2로 진행한다.

**경량 재검** (base_url_hint·dev_command 교차확인): analyzer 보고의 `base_url_hint`·`dev_command` 를 `package.json` 의 `scripts` 와 1회 교차확인한다. 불일치 시 `package.json` 값을 우선한다.

---

## Step 2. 사용자 의도 확인 (필요 시)

Analyzer 결과가 모호한 경우 `AskUserQuestion`으로 확인:

- 디자인 시스템 미확인 → "어떤 디자인 시스템을 사용하시나요?" (옵션: shadcn/ui, MUI, 사내, 기타)
- 모바일 테스트 필요 여부 → **트리거 조건**: 사용자 요청 문구에 모바일/디바이스/반응형 키워드가 있을 때만 "모바일 테스트도 추가할까요?"로 확인한다. 키워드가 없으면 묻지 않고 기본값(Desktop Chromium 단일 프로젝트 — `playwright.config.ts.tmpl`의 기본 `projects` 구성)으로 진행한다.

---

## Step 3. 패키지 설치 명령 제안

Step 3 이전에 감지된 매니저(analyzer 의 `package_manager`)로 아래 표에서 **한 줄만** 골라 사용자에게 제시한다. 감지된 매니저 행 하나만 제시하고 나머지 행은 노출하지 않는다.

| 매니저 | 설치 + 브라우저 다운로드 |
|---|---|
| pnpm | `pnpm add -D @playwright/test` + `pnpm exec playwright install chromium` |
| npm | `npm i -D @playwright/test` + `npx playwright install chromium` |
| yarn | `yarn add -D @playwright/test` + `yarn exec playwright install chromium` |
| bun | `bun add -d @playwright/test` + `bunx playwright install chromium` |

사용자가 승인하면 Bash로 실행. 거부하면 "수동 실행 후 다음 단계로 진행" 안내.

**설치 실패 처리**: 각 명령의 Bash exit code 를 확인한다. 0 이 아니면 즉시 중단하고, 원인(네트워크/권한/디스크)과 재시도 명령을 사용자에게 보고한 뒤 Step 4 로 넘어가지 않는다.

---

## Step 4. 템플릿 복사·치환

`assets/templates/` 의 각 `*.tmpl` 파일을 프로젝트의 적절한 경로로 복사한다. 치환은 다음 규칙:

| 플레이스홀더 | 치환 값 |
|---|---|
| `{{PACKAGE_MANAGER}}` | analyzer 의 `package_manager` 필드에서 직접 매핑 (pnpm / npm / yarn / bun). *주의*: `playwright.config.ts.tmpl`의 `webServer.command`는 `<매니저> run dev` 형태로 치환된다 — analyzer 의 `dev_command`가 `dev`가 아닌 다른 스크립트명(예: `start`)을 가리키면 치환 후 `command` 값을 그 스크립트명으로 수동 조정한다. |
| `{{BASE_URL}}` | analyzer 의 `base_url_hint` 가 있으면 그대로 채택, 없을 때만 사용자 확인 (기본 `http://localhost:3000`) |

> **선택적 하위모델 위임**: 위 치환 맵(`{{PACKAGE_MANAGER}}`, `{{BASE_URL}}`)이 모두 확정되면 4.1 의 템플릿 복사·치환·쓰기를 `general-purpose`(`model: "haiku"`) 서브에이전트 1회 디스패치로 위임할 수 있다(선택). 단 **4.3 AGENTS.md marker-block 병합은 메인 스레드가 직접 수행**한다(멱등·충돌 회피 판단이 필요). 위임 후 메인이 게이트로 검증한다 — 생성 파일 개수 확인 + `grep -r "{{" e2e playwright.config.ts` 미치환 `{{}}` 0건.

### 4.1 생성 파일 목록

| 출처 템플릿 | 대상 경로 |
|---|---|
| `playwright.config.ts.tmpl` | `playwright.config.ts` |
| `fixtures.ts.tmpl` | `e2e/fixtures.ts` |
| `apiMockHandlers.ts.tmpl` | `e2e/mocks/apiMockHandlers.ts` |
| `helpers/DialogHelper.ts.tmpl` | `e2e/helpers/DialogHelper.ts` |
| `helpers/FormHelper.ts.tmpl` | `e2e/helpers/FormHelper.ts` |
| `helpers/SelectHelper.ts.tmpl` | `e2e/helpers/SelectHelper.ts` |
| `helpers/TableHelper.ts.tmpl` | `e2e/helpers/TableHelper.ts` |
| `helpers/NavigationHelper.ts.tmpl` | `e2e/helpers/NavigationHelper.ts` |
| `helpers/ToastHelper.ts.tmpl` | `e2e/helpers/ToastHelper.ts` |
| `helpers/CheckboxHelper.ts.tmpl` | `e2e/helpers/CheckboxHelper.ts` |
| `helpers/RadioGroupHelper.ts.tmpl` | `e2e/helpers/RadioGroupHelper.ts` |
| `helpers/FileUploadHelper.ts.tmpl` | `e2e/helpers/FileUploadHelper.ts` |
| `spec.example.ts.tmpl` | `e2e/tests/example/specs/landing.spec.ts` |
| `flows.example.ts.tmpl` | `e2e/tests/example/flows/landing-flows.ts` |
| (빈 디렉터리) | `e2e/shared/sequences/.gitkeep` |

### 4.2 docs/ai/skills/e2e-flow-generator.md 생성

프로젝트 안에 도구 중립적 AI 가이드를 둔다. 내용은 다음을 포함:

```markdown
# e2e-flow-generator

이 저장소에서 E2E 테스트 시나리오를 추가하는 절차.

## 파일 경로 규칙
- spec: `e2e/tests/{도메인}/specs/{시나리오}.spec.ts`
- flow: `e2e/tests/{도메인}/flows/{시나리오}-flows.ts`
- mock: `e2e/mocks/{도메인}-mocks.ts`
- shared sequence: `e2e/shared/sequences/{이름}.ts`

## 사용 가능한 Helper
- DialogHelper: waitForOpen, clickConfirm, close, expectTitle
- FormHelper: fillFields, submit, expectErrors, expectFieldEditable
- SelectHelper: selectByLabel, selectFirstOption, expectSelected
- TableHelper: getRowByText, clickRowAction, expectRowCount, expectRowExists
- NavigationHelper: clickTab, expectUrlMatches, expectActiveTab, expectBreadcrumb, expectMainVisible
- ToastHelper: expectSuccess, expectError, waitForDismiss
- CheckboxHelper: check, uncheck, toggle, expectChecked, checkMultiple
- RadioGroupHelper: selectByLabel, expectSelected
- FileUploadHelper: selectFiles, expectUploadedFile, expectFileCount, removeFile

## Selector 우선순위
1순위: getByRole, 2순위: getByLabel/getByPlaceholder, 3순위: [data-slot=...]
영역 스코핑 필수, getByText OR 매칭 금지.

## 자연어 → 코드 매핑 (Phase 2 참고)
(SKILL.md의 매핑표를 그대로 임베드)
```

### 4.3 AGENTS.md 등록 (marker block 패턴)

루트 `AGENTS.md` 에 e2e-flow 스킬 등록. 다른 도구(예: Next.js `create-next-app` 의 `--agents-md` default)가 이미 자체 marker block을 박아둘 수 있으므로, **e2e-flow도 자체 marker block으로 감싸** 추가한다. 멱등 보장 + 충돌 회피.

```markdown
<!-- BEGIN:e2e-flow-skill -->
## 사용 가능한 스킬

- **e2e-flow-generator**: Playwright E2E 시나리오를 추가할 때 참조합니다.
  (파일: `docs/ai/skills/e2e-flow-generator.md`)
<!-- END:e2e-flow-skill -->
```

**처리 규칙**:
- `AGENTS.md` 없음 → 새로 생성, 위 block을 본문으로
- 있는데 `<!-- BEGIN:e2e-flow-skill -->` 마커 없음 → 파일 끝에 빈 줄 + block append
- 있고 마커 있음 → 마커 사이 내용을 *치환* (단순 append 금지 — 중복 누적)

다른 도구의 marker block(예: `<!-- BEGIN:nextjs-agent-rules -->`)은 건드리지 않는다.

### 4.4 package.json 스크립트 추가

```diff
{
  "scripts": {
+   "test:e2e": "playwright test --grep-invert=@vrt",
+   "test:vrt": "playwright test --grep @vrt",
+   "test:vrt-update": "playwright test --grep @vrt --update-snapshots",
+   "test:e2e:ui": "playwright test --ui"
  }
}
```

기존 스크립트와 충돌하면 사용자에게 확인.

### 4.5 .gitignore 항목 추가

```
test-results/
playwright-report/
playwright/.cache/
e2e/.auth/
```

---

## Step 5. 검증 게이트 (오케스트레이터가 직접 실행)

사용자 안내가 아니라 오케스트레이터가 **직접 실행해 통과 여부를 판정**하는 게이트다. 두 게이트를 순서대로 실행한다.

**게이트 1 — 미치환 토큰 0건**:

```bash
grep -r "{{" e2e playwright.config.ts || true
```

**exit code 가 아니라 stdout 출력으로 판정한다** — `grep` 은 매칭이 0건(= 미치환 토큰 없음 = 통과)일 때 exit code `1` 을 반환하므로, exit code 로 성공/실패를 가리면 정상 상태를 실패로 오인한다. `|| true` 로 exit code 를 무력화하고, **출력이 비어 있으면 통과**, 한 줄이라도 나오면 실패로 본다. 실패 시 해당 파일의 미치환 플레이스홀더를 채운 뒤 재실행한다.

**게이트 2 — spec 트랜스파일 + 리스트**: 로컬 playwright 바이너리를 실행한다. 실행 프리픽스는 매니저별로 다르므로 아래 표에서 감지된 매니저의 명령을 **그대로** 쓴다 (`exec` 를 무조건 붙이지 말 것 — `npx exec`/`bunx exec` 는 잘못된 명령이다):

| 매니저 | 실행 명령 |
|---|---|
| pnpm | `pnpm exec playwright test --list` |
| npm | `npx playwright test --list` |
| yarn | `yarn exec playwright test --list` |
| bun | `bunx playwright test --list` |

예시 테스트가 1개 이상 리스트되어야 한다 (이 명령이 spec 트랜스파일을 겸하므로 컴파일 에러가 여기서 드러난다). 리스트 결과가 0개거나 에러면 실패.

**tsc --noEmit (참고용, 비차단)**: `tsc` 가 `devDependencies` 에 있으면 위 표와 같은 프리픽스로 `tsc --noEmit` 도 실행한다 (pnpm/yarn 은 `<매니저> exec tsc --noEmit`, npm 은 `npx tsc --noEmit`, bun 은 `bunx tsc --noEmit`). 이 결과는 필수 차단 게이트가 아니다 — 이번에 새로 생성한 `e2e/` 하위 파일과 `playwright.config.ts`에서 발생한 에러만 차단 사유로 보고 원인을 수정한다. 그 외 기존 앱 코드의 타입 에러는 결과에 보고만 하고 Phase 1 완료를 막지 않는다.

**if-then 판정**:

- 필수 차단 게이트는 두 가지뿐이다: (1) 게이트 1 — 미치환 토큰 0건, (2) 게이트 2 — `playwright test --list` 결과 1개 이상. 이 둘이 모두 통과하면 **그때만** Step 6 성공 보고로 진행한다 (tsc --noEmit의 기존 앱 코드 에러는 판정에 영향 없음).
- 게이트 1 또는 게이트 2가 하나라도 실패 → 실패 원인(어느 게이트, 어떤 파일/에러)을 보고하고 **"✅ 완료"를 선언하지 않는다**. 원인 수정 후 게이트를 재실행한다. (새로 생성한 e2e 파일·playwright.config.ts에서 tsc 에러가 난 경우도 동일하게 수정 후 재실행)

---

## Step 6. 사용자 보고

다음 요약을 출력한다:

```
✅ Phase 1 완료

생성된 파일:
- playwright.config.ts
- e2e/helpers/ (9개 Helper)
- e2e/fixtures.ts
- e2e/mocks/apiMockHandlers.ts
- e2e/tests/example/ (예시 spec/flow 1쌍)
- e2e/shared/sequences/
- docs/ai/skills/e2e-flow-generator.md
- AGENTS.md (사용 가능한 스킬 항목 추가)

다음 단계:
- 테스트 추가: "어떤 페이지의 어떤 동작" 자연어로 요청
  예) "로그인 페이지에서 잘못된 비밀번호 입력하면 에러 토스트 뜨는지 확인"
- VRT 추가: "VRT 붙여줘"
- CI 추가: "GitHub Actions로 E2E 워크플로우 추가해줘"
```

라우팅에서 보관한 원본 시나리오가 있으면 사용자 재입력 없이 곧바로 **Phase 2로 자동 진입**한다(A6). 없으면 추가 시나리오 요청이 들어올 때 Phase 2로 진입한다.

---

## 부분 재셋업 절차 (config 있음 + Helper 9종 중 일부 누락)

SKILL.md 라우팅 표 2행("config 있음 + Helper 9종 중 일부 누락")이 진입하는 절차다. 위 Step 1~6 전체를 처음부터 다시 실행하지 않고, 아래 (a)~(f)만 이 순서로 실행한다.

**(a) Codebase Analyzer 재디스패치 생략**: Step 1의 서브에이전트 호출은 하지 않는다. 패키지 매니저만 `references/phase-3-self-heal.md` Step 0의 A7 lockfile 우선순위 규칙(`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `package-lock.json` → npm, `bun.lock`/`bun.lockb` → bun, 없으면 `packageManager` 필드, 그래도 없으면 `npx` 폴백)으로 재확인한다.

**(b) Step 3(패키지 설치) 생략**: `package.json`의 `devDependencies`에 `@playwright/test`가 있는지만 확인한다. 있으면 설치 단계를 건너뛴다. 없으면 부분 재셋업을 중단하고 Step 1부터 전체 셋업으로 전환한다(신호 2가 부분 셋업으로 오판된 경우이므로).

**(c) Step 4.1 중 누락된 Helper 템플릿만 복사·치환**: 4.1 표에서 Glob으로 확인된 누락 Helper 행만 복사·치환한다. 이미 존재하는 Helper 파일, `playwright.config.ts`, `apiMockHandlers.ts` 등 다른 파일은 건드리지 않는다.

**(d) fixtures.ts는 덮어쓰지 않는다**: 이미 `e2e/fixtures.ts`가 존재하면 `fixtures.ts.tmpl`로 전체 교체하지 않는다. 대신 누락됐던 Helper의 import문 · `Helpers` 인터페이스 필드 · `test.extend` 안 fixture 정의, 이 3곳을 증분(diff)으로 추가한다 — 패턴은 `references/playwright-fixtures.md`의 'TypeScript 타입 확장 패턴' 절을 그대로 따른다. `e2e/fixtures.ts`가 아예 없는 경우에만 `fixtures.ts.tmpl`을 전체 복사한다.

**(e) Step 5 검증 게이트 재실행**: 위 Step 5의 두 필수 게이트(미치환 토큰 0건, `playwright test --list` ≥ 1)를 동일한 기준으로 재실행한다. if-then 판정도 동일하게 적용한다.

**(f) 보고**: Step 6과 다른 축약 형식으로 보고한다.

```
✅ 부분 재셋업 완료: 생성 N개 / 증분 갱신 fixtures.ts

생성된 파일:
- e2e/helpers/{누락됐던 Helper 이름}.ts (N개)
- (e2e/fixtures.ts가 아예 없었던 경우만) e2e/fixtures.ts
```

라우팅에서 보관한 원본 시나리오가 있으면 Step 6과 동일하게 곧바로 Phase 2로 자동 진입한다(A6).
