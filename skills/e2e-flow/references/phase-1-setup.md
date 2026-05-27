# Phase 1 — 인프라 셋업 절차

프로젝트에 `playwright.config.*` 가 없을 때 실행하는 셋업 페이즈. **Codebase Analyzer 서브에이전트**를 한 번 디스패치한 뒤, 결과에 따라 메인 스레드에서 템플릿을 복사·치환한다.

---

## Step 1. Codebase Analyzer 디스패치

`assets/prompts/codebase-analyzer.md` 의 프롬프트로 `Explore` 서브에이전트를 호출한다.

```text
Agent({
  description: "Frontend codebase analysis for E2E setup",
  subagent_type: "Explore",
  prompt: <assets/prompts/codebase-analyzer.md 내용을 그대로 사용>
})
```

**기대 출력** (200단어 이내, 구조화):
- 프레임워크: Next.js (App Router) / Next.js (Pages) / Vite / CRA / 그 외
- 패키지 매니저: pnpm / npm / yarn / bun
- 디자인 시스템: shadcn/ui / MUI / Chakra / Mantine / 사내 / 미확인
- 라우팅: 파일 기반 / React Router / 기타
- 기존 테스트: 있음/없음 (Jest, Vitest, Cypress 흔적)
- 환경변수 패턴: `.env.local` / `.env.development` 등

---

## Step 2. 사용자 의도 확인 (필요 시)

Analyzer 결과가 모호한 경우 `AskUserQuestion`으로 확인:

- 디자인 시스템 미확인 → "어떤 디자인 시스템을 사용하시나요?" (옵션: shadcn/ui, MUI, 사내, 기타)
- 모바일 테스트 필요 여부 → playwright.config의 projects 구성에 영향

---

## Step 3. 패키지 설치 명령 제안

사용자에게 다음 명령을 안내 (직접 실행하지 않고, 명확한 안내만):

```bash
# pnpm 기준
pnpm add -D @playwright/test
pnpm exec playwright install chromium
```

사용자가 승인하면 Bash로 실행. 거부하면 "수동 실행 후 다음 단계로 진행" 안내.

---

## Step 4. 템플릿 복사·치환

`assets/templates/` 의 각 `*.tmpl` 파일을 프로젝트의 적절한 경로로 복사한다. 치환은 다음 규칙:

| 플레이스홀더 | 치환 값 |
|---|---|
| `{{PACKAGE_MANAGER}}` | pnpm / npm / yarn |
| `{{FRAMEWORK}}` | next / vite / cra |
| `{{BASE_URL}}` | 사용자에게 확인 (기본 `http://localhost:3000`) |
| `{{DESIGN_SYSTEM_HINT}}` | 감지된 디자인 시스템 이름 (주석용) |

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
- NavigationHelper: clickTab, expectUrlMatches, expectActiveTab, expectBreadcrumb
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

## Step 5. 검증

설치 후 다음 명령으로 셋업이 정상인지 확인 (사용자에게 안내):

```bash
pnpm exec playwright test --list
# 예시 테스트가 1개 이상 리스트되어야 한다
```

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

추가 시나리오 요청이 들어오면 **Phase 2로 자동 진입**.
