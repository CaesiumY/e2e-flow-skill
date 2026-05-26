# Playwright Fixture 자동 주입 패턴

Helper 9종을 매 테스트마다 수동 초기화하지 않고, Playwright의 `test.extend`로 **fixture 자동 주입**한다. 테스트는 `async ({ form, dialog, toast }) => {...}` 형태로 Helper를 바로 받아 쓴다.

## 핵심 fixtures.ts

`assets/templates/fixtures.ts.tmpl` 로부터 프로젝트의 `e2e/fixtures.ts` 로 복사된다.

```ts
// e2e/fixtures.ts
import { test as base, type Page } from '@playwright/test';
import { DialogHelper } from './helpers/DialogHelper';
import { FormHelper } from './helpers/FormHelper';
import { SelectHelper } from './helpers/SelectHelper';
import { TableHelper } from './helpers/TableHelper';
import { NavigationHelper } from './helpers/NavigationHelper';
import { ToastHelper } from './helpers/ToastHelper';
import { apiMockHandlers, type MockHandler } from './mocks/apiMockHandlers';

interface Helpers {
  dialog: DialogHelper;
  form: FormHelper;
  select: SelectHelper;
  table: TableHelper;
  navigation: NavigationHelper;
  toast: ToastHelper;
}

interface MockFixture {
  /** 테스트 단위로 API 모킹을 설정. */
  setMocks: (handlers: MockHandler[]) => Promise<void>;
}

export const test = base.extend<Helpers & MockFixture>({
  dialog: async ({ page }, use) => use(new DialogHelper(page)),
  form: async ({ page }, use) => use(new FormHelper(page)),
  select: async ({ page }, use) => use(new SelectHelper(page)),
  table: async ({ page }, use) => use(new TableHelper(page)),
  navigation: async ({ page }, use) => use(new NavigationHelper(page)),
  toast: async ({ page }, use) => use(new ToastHelper(page)),

  setMocks: async ({ page }, use) => {
    await use(async (handlers) => {
      await apiMockHandlers(page, handlers);
    });
  },
});

export { expect } from '@playwright/test';
```

## 사용 예

```ts
// e2e/tests/agent/specs/create.spec.ts
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

flow 함수는 fixture 묶음을 인자로 받는다 (의존성 명시화).

```ts
// e2e/tests/agent/flows/create-flows.ts
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

---

## API Mock fixture

`apiMockHandlers`는 네트워크 인터셉터를 등록한다. 매처 함수 + 응답 본문 쌍의 배열을 받는다.

```ts
// e2e/mocks/apiMockHandlers.ts
import type { Page, Route } from '@playwright/test';

export interface MockHandler {
  /** URL과 메서드를 매칭하는 함수. true 반환 시 응답 가로채기. */
  match: (url: string, method: string) => boolean;
  responseBody: unknown;
  status?: number;
}

export async function apiMockHandlers(page: Page, handlers: MockHandler[]): Promise<void> {
  await page.route('**/*', async (route: Route) => {
    const request = route.request();
    const matched = handlers.find((h) => h.match(request.url(), request.method()));
    if (matched) {
      await route.fulfill({
        status: matched.status ?? 200,
        contentType: 'application/json',
        body: JSON.stringify(matched.responseBody),
      });
      return;
    }
    await route.continue();
  });
}

/** URL signature 매처 헬퍼. */
export function signatureMatch(signature: { path: string; method: string }) {
  return (url: string, method: string) =>
    method.toUpperCase() === signature.method.toUpperCase() && new URL(url).pathname.endsWith(signature.path);
}
```

도메인별 mock 설정 함수:

```ts
// e2e/mocks/agent-mocks.ts
import { signatureMatch, type MockHandler } from './apiMockHandlers';
import { AGENT_FIXTURE } from '../fixtures/agent-fixture';

export function setAgentCreateMocks(): MockHandler[] {
  return [
    {
      match: signatureMatch({ path: '/api/agents', method: 'POST' }),
      responseBody: AGENT_FIXTURE.CREATE_SUCCESS,
    },
    {
      match: signatureMatch({ path: '/api/models', method: 'GET' }),
      responseBody: AGENT_FIXTURE.MODELS_LIST,
    },
  ];
}
```

---

## fixture 데이터 (zod 권장)

fixture(테스트 데이터)는 타입 안전을 위해 zod 스키마와 함께 정의하는 것을 권장한다. Storybook과 E2E가 같은 데이터를 공유할 수 있다.

```ts
// e2e/fixtures/agent-fixture.ts
import { z } from 'zod';

export const AgentSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string(),
  model: z.string(),
});

export const AGENT_FIXTURE = {
  CREATE_SUCCESS: { data: AgentSchema.parse({
    id: 'agent_1',
    name: '테스트 에이전트',
    description: '테스트용',
    model: 'gpt-4o',
  })},
  MODELS_LIST: { data: [{ id: 'gpt-4o', name: 'GPT-4o' }] },
};
```

---

## shared/sequences — 공통 선행 동작

로그인처럼 여러 spec에서 반복되는 선행 동작은 `e2e/shared/sequences/`로 분리한다.

```ts
// e2e/shared/sequences/login.ts
import type { Page } from '@playwright/test';
import { FormHelper } from '../../helpers/FormHelper';

export async function userLoginSuccessSequence(page: Page): Promise<void> {
  await page.goto('/login');
  const form = new FormHelper(page);
  await form.fillFields({ 이메일: 'test@example.com', 비밀번호: 'test1234' });
  await form.submit('로그인');
  await page.waitForURL('/dashboard');
}
```

```ts
// 사용
test.beforeEach(async ({ page }) => {
  await userLoginSuccessSequence(page);
  await page.goto('/contracts/new');
});
```

sequence는 여러 flow의 결합이므로 **단일 flow로 보기 어려운 경우**에 사용. 단일 행동이면 flow에 둔다.

---

## TypeScript 타입 확장 패턴

> v0.2.0에서 `CheckboxHelper`, `RadioGroupHelper`, `FileUploadHelper` Tier A 3종이 추가되어 fixture는 총 9개 Helper를 자동 주입한다. 아래 diff는 *새 Helper를 추가할 때의 패턴*을 보여주는 예시.

fixture에 새 Helper를 추가할 때:

1. `e2e/helpers/{NewHelper}.ts` 작성
2. `e2e/fixtures.ts`의 `Helpers` 인터페이스에 추가
3. `test.extend` 안에 fixture 정의 추가

```diff
interface Helpers {
  dialog: DialogHelper;
+ fileUpload: FileUploadHelper;
}

export const test = base.extend<Helpers & MockFixture>({
  dialog: async ({ page }, use) => use(new DialogHelper(page)),
+ fileUpload: async ({ page }, use) => use(new FileUploadHelper(page)),
});
```

이후 모든 spec에서 `async ({ fileUpload })` 로 즉시 사용 가능.
