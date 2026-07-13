# Phase 2 — 테스트 생성 절차

자연어 시나리오 입력을 받아 규칙 준수 spec/flow 파일을 생성한다. 메인 스레드에서 수행(서브에이전트 없음). 생성 후 곧바로 **Phase 3 자가 복구**로 이어진다.

---

## Step 1. 자연어 입력 파싱

Phase 1 라우팅에서 보관·전달된 원본 시나리오가 있으면 그것을 입력으로 사용한다 (사용자 재입력 불필요).

사용자 입력을 다음 4요소로 분해한다:

| 요소 | 추출 단서 | 예 |
|---|---|---|
| **도메인** | 페이지/기능명 | "에이전트 생성 페이지" → `agent` |
| **시작 경로** | "X 페이지에서", URL 흔적 | `/ai-agent/create` |
| **액션 시퀀스** | 동사+목적어 나열 | 입력 → 클릭 → 모달 확인 |
| **검증 포인트** | "~ 뜨는지", "~ 확인" | 성공 토스트 / URL 이동 / 에러 메시지 |

도메인이 불명확하면 `AskUserQuestion` 으로 확인. 기존 `e2e/tests/` 의 도메인 디렉터리 목록을 보여주고 신규/기존 선택.

**시작 경로 해소 규칙**: 사용자 입력에 URL/경로 단서가 없으면 다음 순서로 해소한다:
1. 같은 도메인의 기존 spec에서 `page.goto()` 경로를 재사용
2. 기존 spec도 없으면 `AskUserQuestion` 으로 시작 경로를 확인

페이지명에서 URL을 추론하지 않는다 — 근거(기존 spec 또는 사용자 응답) 있는 경로만 사용한다.

---

## Step 2. 컨텍스트 로딩

다음을 순서대로 Read한다:

1. **Helper 카탈로그**: `e2e/helpers/*.ts` 의 클래스명·메서드 시그니처 추출 (전체 Read 불필요, Grep으로 `export class|async (\w+)\(` 정도면 충분)
2. **가장 가까운 도메인 패턴**: Glob(`e2e/tests/**/*.spec.ts`, `e2e/tests/**/*-flows.ts`)으로 후보를 나열한 뒤, 다음 우선순위로 참조할 spec/flow 1쌍을 결정해 Read (전체 스캔 불필요):
   1. 정확히 같은 `{도메인}` 디렉터리(`e2e/tests/{도메인}/`)가 있으면 그 안에서 가장 최근 수정된(mtime) spec/flow 1쌍
   2. 없으면 `e2e/tests/` 전체에서 가장 최근 수정된(mtime) spec/flow 1쌍
   3. 그래도 없으면 `e2e/tests/example/`
3. **기존 mock 패턴**: `e2e/mocks/` 의 임의 1개 Read (있는 경우)
4. **fixture 카탈로그**: `e2e/fixtures/` (있는 경우)

---

## Step 3. 파일 생성

### 3.1 spec 파일

경로: `e2e/tests/{도메인}/specs/{시나리오-kebab}.spec.ts`

**내용 원칙**:
- 자연어에 가까운 행동 함수 호출만 (구현 디테일은 flow에)
- `test.describe(...)` 로 그룹화
- 선행 동작 있으면 `beforeEach`에 sequence 호출
- 가장 자주 쓰는 fixture만 `async ({ page, form, dialog, toast })` 로 디스트럭처링

```ts
import { test } from '../../../fixtures';
import { 에이전트_생성_플로우 } from '../flows/create-flows';
import { setAgentCreateMocks } from '../../../mocks/agent-mocks';

test.describe('에이전트 생성', () => {
  test.beforeEach(async ({ setMocks }) => {
    await setMocks(setAgentCreateMocks());
  });

  test('정상 생성 플로우', async ({ page, form, dialog, toast }) => {
    await page.goto('/ai-agent/create');
    await 에이전트_생성_플로우({ page, form, dialog, toast });
  });
});
```

### 3.2 flow 파일

경로: `e2e/tests/{도메인}/flows/{시나리오-kebab}-flows.ts`

**내용 원칙**:
- flow 함수는 fixture 묶음을 인자로 받는다 (의존성 명시화)
- 한 flow = 하나의 의미 단위 (예: `자격_증명_입력`, `에이전트_생성_플로우`)
- Helper 메서드 조합으로 작성, 저수준 Playwright API 직접 사용 금지
- 자연어→코드 매핑 규칙(`SKILL.md`)을 따른다

```ts
import type { Page } from '@playwright/test';
import type { FormHelper } from '../../../helpers/FormHelper';
import type { DialogHelper } from '../../../helpers/DialogHelper';
import type { ToastHelper } from '../../../helpers/ToastHelper';

interface CreateContext {
  page: Page;
  form: FormHelper;
  dialog: DialogHelper;
  toast: ToastHelper;
}

export async function 에이전트_생성_플로우({ form, dialog, toast }: CreateContext) {
  await form.fillFields({
    '에이전트 이름': '테스트 에이전트',
    '설명': '테스트용 에이전트입니다',
  });
  await form.submit('저장');
  await dialog.clickConfirm('생성');
  await toast.expectSuccess();
}
```

### 3.3 mock 파일 (필요한 경우)

경로: `e2e/mocks/{도메인}-mocks.ts`

API 호출이 있는 시나리오면 mock 핸들러를 함께 생성한다. fixture 데이터가 없으면 `e2e/fixtures/{도메인}-fixture.ts` 도 함께 생성.

```ts
import { signatureMatch, type MockHandler } from './apiMockHandlers';
import { AGENT_FIXTURE } from '../fixtures/agent-fixture';

export function setAgentCreateMocks(): MockHandler[] {
  return [
    {
      match: signatureMatch({ path: '/api/agents', method: 'POST' }),
      responseBody: AGENT_FIXTURE.CREATE_SUCCESS,
    },
  ];
}
```

---

## Step 4. data-testid 누락 검토

생성 직전, 만든 selector들 중 Selector 우선순위 1·2순위로 잡을 수 없는 컴포넌트가 있다면:

1. 해당 컴포넌트 소스를 Grep으로 찾는다 (예: `<Dialog>...에이전트 생성...</Dialog>`)
2. 권장 패치를 diff로 제시:
   ```diff
   - <Section>
   + <Section data-testid="agent-form-section">
   ```
3. **사용자에게 결정 위임** — 즉시 적용할지, 보류할지.

자세한 기준: `references/selector-priority.md` → "data-testid 추가 권장 시나리오"

---

## Step 4.5. 생성물 정적 검증 게이트

Step 3에서 생성한 spec/flow/mock이 실제로 컴파일·트랜스파일 가능한지 Phase 3 진입 **전**에 검증한다. **여기서 에러가 발견되면 Phase 3(자가 복구) 진입을 금지한다.** 컴파일/타입/import 에러는 자가 복구 4분류(UI_CHANGE/TEST_BUG/APP_BUG/ENV_ISSUE) 대상이 아니다 — Self-Healer를 디스패치하지 않고 메인 스레드가 직접 수정한다.

### (a) Helper 메서드 실재 여부 대조

생성한 flow/spec이 호출하는 Helper 메서드(예: `form.fillFields`, `dialog.clickConfirm`)를 추출해, 실제 `e2e/helpers/*.ts` 에 해당 메서드가 존재하는지 Grep으로 대조한다.

```bash
# 아래 패턴은 예시다. 실제로는 방금 생성한 flow/spec에서 호출한 메서드명을 추출해
# 파이프(\|)로 이어 동적으로 구성한다: grep -n "<추출한 메서드들 | 로 연결>" e2e/helpers/*.ts
grep -n "fillFields\|clickConfirm\|expectSuccess" e2e/helpers/*.ts
```

호출한 메서드가 존재하지 않으면 → 해당 flow/spec 파일을 직접 수정 (실재하는 메서드로 교체).

### (b) 트랜스파일 확인

패키지 매니저는 Phase 1에서 감지된 값 사용. `tsc`가 devDependencies에 있으면 우선 사용:

```bash
pnpm exec tsc --noEmit
# 또는 npx tsc --noEmit
```

없으면 Playwright `--list`로 트랜스파일만 확인 (실행 없이 목록화):

```bash
pnpm exec playwright test {생성한 spec 경로} --list
# 또는 npx playwright test {생성한 spec 경로} --list
```

TS 컴파일 에러(`TS####`), `SyntaxError`, `Cannot find module` 등이 나오면 → import 경로·시그니처를 직접 수정.

### if-then 진행 규칙

- **에러 발견** → 해당 파일을 메인 스레드가 직접 수정 → (a)·(b) 재검증 → 통과할 때까지 반복
- **통과** → Step 5로 진행

---

## Step 5. 즉시 Phase 3로 진입

Step 4.5 게이트를 통과한 직후, 사용자 확인 없이 곧바로 `references/phase-3-self-heal.md` 의 절차로 진입해 테스트를 실행하고 자가 복구 루프를 돌린다.

Phase 3 진입 시 인자:
- 대상 테스트 파일: 방금 생성한 `{시나리오}.spec.ts`
- 컨텍스트: 자연어 입력, 생성된 파일 목록
- 상태: 생성 직후 첫 진입임 (Step 4.5 사전 필터·정적 검증 게이트 통과 상태)

---

## 네이밍 규칙

| 항목 | 규칙 | 예 |
|---|---|---|
| 도메인 디렉터리 | kebab-case 영문 | `agent`, `data-source`, `chat` |
| spec 파일 | `{시나리오-kebab}.spec.ts` | `create.spec.ts`, `edit-error.spec.ts` |
| flow 파일 | `{시나리오-kebab}-flows.ts` | `create-flows.ts` |
| mock 파일 | `{도메인}-mocks.ts` | `agent-mocks.ts` |
| flow 함수명 | 한국어 가능, snake_case 권장 | `에이전트_생성_플로우`, `자격_증명_입력` |
| test 이름 | 한국어 자연어 | `'정상 생성 플로우'` |

---

## 안티패턴 (생성 시 절대 금지)

```ts
// ❌ 저수준 Playwright API를 spec에 직접 사용
test('생성', async ({ page }) => {
  await page.getByLabel('이름').fill('X');
  await page.getByRole('button', { name: '저장' }).click();
});

// ✅ Helper 사용
test('생성', async ({ page, form }) => {
  await form.fillFields({ 이름: 'X' });
  await form.submit('저장');
});
```

```ts
// ❌ flow에 저수준 API 직접 사용
export async function 생성_플로우(page: Page) {
  await page.getByLabel('이름').fill('X');
}

// ✅ flow도 Helper를 받아 사용
export async function 생성_플로우({ form }: Ctx) {
  await form.fillFields({ 이름: 'X' });
}
```

```ts
// ❌ spec에 mock 설정 직접 작성
test.beforeEach(async ({ page }) => {
  await page.route('**/api/**', ...);
});

// ✅ mock 파일 분리 + setMocks fixture 사용
test.beforeEach(async ({ setMocks }) => {
  await setMocks(setAgentCreateMocks());
});
```

---

## Phase 3 복귀 진입 (재생성 계약)

Phase 3가 3회 시도를 모두 소진하고, 누적 분류가 **TEST_BUG로 수렴**하며, 마지막 가설이 **flow 구조 자체의 문제**를 가리키는 경우, Phase 3 최종 보고의 옵션으로 "Phase 2 재생성"이 제시된다. 사용자가 이 옵션을 선택하면 Phase 2는 사용자 재입력 없이 다음을 입력으로 받아 재진입한다:

| 입력 | 내용 |
|---|---|
| 원본 자연어 시나리오 | 최초 Phase 2 진입 시의 입력 (그대로 재사용) |
| 이전 실패 이력 | 시도별 분류(UI_CHANGE/TEST_BUG/APP_BUG/ENV_ISSUE)·적용한 edits 요약 |
| 마지막 가설 | Self-Healer 마지막 응답의 reasoning |

**재설계 원칙**: Step 1~4를 다시 수행하되, "마지막 가설"이 지목한 접근(예: 특정 selector 조합, 특정 flow 분해 방식)은 **명시적으로 배제**하고 다른 구조로 flow를 재설계한다 — 실패한 접근을 그대로 반복하지 않는다. 재생성한 spec/flow는 Step 4.5 게이트를 다시 통과한 뒤 Step 5로 Phase 3에 재진입한다.
