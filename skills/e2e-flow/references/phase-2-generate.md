# Phase 2 — 테스트 생성 절차

자연어 시나리오 입력을 받아 규칙 준수 spec/flow 파일을 생성한다. 메인 스레드에서 수행(서브에이전트 없음). 생성 후 곧바로 **Phase 3 자가 복구**로 이어진다.

---

## Step 1. 자연어 입력 파싱

사용자 입력을 다음 4요소로 분해한다:

| 요소 | 추출 단서 | 예 |
|---|---|---|
| **도메인** | 페이지/기능명 | "에이전트 생성 페이지" → `agent` |
| **시작 경로** | "X 페이지에서", URL 흔적 | `/ai-agent/create` |
| **액션 시퀀스** | 동사+목적어 나열 | 입력 → 클릭 → 모달 확인 |
| **검증 포인트** | "~ 뜨는지", "~ 확인" | 성공 토스트 / URL 이동 / 에러 메시지 |

도메인이 불명확하면 `AskUserQuestion` 으로 확인. 기존 `e2e/tests/` 의 도메인 디렉터리 목록을 보여주고 신규/기존 선택.

---

## Step 2. 컨텍스트 로딩

다음을 순서대로 Read한다:

1. **Helper 카탈로그**: `e2e/helpers/*.ts` 의 클래스명·메서드 시그니처 추출 (전체 Read 불필요, Grep으로 `export class|async (\w+)\(` 정도면 충분)
2. **가장 가까운 도메인 패턴**: 같은 도메인 또는 유사한 도메인의 `*.spec.ts`, `*-flows.ts` 1~2개 Read해 네이밍·구조 학습
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

## Step 5. 즉시 Phase 3로 진입

생성 직후, 사용자 확인 없이 곧바로 `references/phase-3-self-heal.md` 의 절차로 진입해 테스트를 실행하고 자가 복구 루프를 돌린다.

Phase 3 진입 시 인자:
- 대상 테스트 파일: 방금 생성한 `{시나리오}.spec.ts`
- 컨텍스트: 자연어 입력, 생성된 파일 목록

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
