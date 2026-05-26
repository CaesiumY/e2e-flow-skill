# Helper 6종 완성 코드

디자인 시스템 컴포넌트와 1:1 매핑되는 Helper 6개. Phase 1에서 `assets/templates/helpers/*.tmpl` 로부터 프로젝트의 `e2e/helpers/` 에 복사·치환된다.

각 Helper는:
- **자연어에 가까운 메서드명** (`fillFields`, `clickConfirm`, `expectSuccess` 등)
- **Selector 우선순위 규칙 내장** (`references/selector-priority.md`)
- **Playwright Fixture로 자동 주입** (`references/playwright-fixtures.md`)

---

## 공통 베이스 타입

```ts
// e2e/helpers/types.ts
import type { Page, Locator } from '@playwright/test';

export interface HelperContext {
  readonly page: Page;
}
```

---

## DialogHelper

다이얼로그/모달의 열림 대기, 확인 버튼 클릭, 닫기를 담당.

```ts
// e2e/helpers/DialogHelper.ts
import { expect, type Page, type Locator } from '@playwright/test';

export class DialogHelper {
  constructor(private readonly page: Page) {}

  /** 모달이 열릴 때까지 대기. 이름 지정 시 해당 모달만. */
  async waitForOpen(name?: string | RegExp): Promise<Locator> {
    const dialog = name
      ? this.page.getByRole('dialog', { name })
      : this.page.getByRole('dialog');
    await expect(dialog).toBeVisible();
    return dialog;
  }

  /** 모달 내부의 확인/생성/삭제 등 액션 버튼 클릭. */
  async clickConfirm(buttonName: string | RegExp = '확인'): Promise<void> {
    const dialog = this.page.getByRole('dialog');
    await expect(dialog).toBeVisible();
    await dialog.getByRole('button', { name: buttonName }).click();
  }

  /** 모달 닫기 — 닫기/취소 버튼 우선. */
  async close(): Promise<void> {
    const dialog = this.page.getByRole('dialog');
    await dialog.getByRole('button', { name: /닫기|취소|cancel|close/i }).click();
  }

  /** 모달 제목 검증. */
  async expectTitle(title: string | RegExp): Promise<void> {
    const dialog = this.page.getByRole('dialog');
    await expect(dialog.getByRole('heading')).toHaveText(title);
  }
}
```

---

## FormHelper

폼 입력, 제출, 에러 메시지 검증.

```ts
// e2e/helpers/FormHelper.ts
import { expect, type Page } from '@playwright/test';

export class FormHelper {
  constructor(private readonly page: Page) {}

  /** label-value 쌍을 받아 차례로 입력. */
  async fillFields(fields: Record<string, string>): Promise<void> {
    for (const [label, value] of Object.entries(fields)) {
      const field = this.page.getByLabel(label);
      await expect(field).toBeEditable();
      await field.fill(value);
    }
  }

  /** 제출 버튼 클릭. label은 디자인 시스템 기본값에 맞춰 조정. */
  async submit(label: string | RegExp = '저장'): Promise<void> {
    await this.page.getByRole('button', { name: label }).click();
  }

  /** 폼 에러 메시지 검증 — 개별 locator로 각각 (strict mode 안전). */
  async expectErrors(messages: string[]): Promise<void> {
    for (const msg of messages) {
      await expect(this.page.getByText(msg)).toBeVisible();
    }
  }

  /** 특정 필드가 비활성/활성 상태인지 검증. */
  async expectFieldEditable(label: string, editable = true): Promise<void> {
    const field = this.page.getByLabel(label);
    if (editable) await expect(field).toBeEditable();
    else await expect(field).toBeDisabled();
  }
}
```

---

## SelectHelper

Select / Combobox 선택.

```ts
// e2e/helpers/SelectHelper.ts
import { expect, type Page } from '@playwright/test';

export class SelectHelper {
  constructor(private readonly page: Page) {}

  /** label로 식별된 select에서 옵션 선택. */
  async selectByLabel(label: string, optionText: string | RegExp): Promise<void> {
    const trigger = this.page.getByLabel(label);
    await trigger.click();
    await this.page
      .getByRole('option', { name: optionText })
      .click();
  }

  /** 첫 번째 옵션 선택 (조건 자동 통과용). */
  async selectFirstOption(label: string): Promise<void> {
    const trigger = this.page.getByLabel(label);
    await trigger.click();
    await this.page.getByRole('option').first().click();
  }

  /** 현재 선택된 옵션 검증. */
  async expectSelected(label: string, expectedText: string | RegExp): Promise<void> {
    await expect(this.page.getByLabel(label)).toHaveText(expectedText);
  }
}
```

---

## TableHelper

DataTable 의 행 식별과 액션.

```ts
// e2e/helpers/TableHelper.ts
import { expect, type Page, type Locator } from '@playwright/test';

export class TableHelper {
  constructor(private readonly page: Page) {}

  /** 특정 텍스트가 포함된 행을 반환. */
  getRowByText(rowText: string | RegExp): Locator {
    return this.page.getByRole('row').filter({ hasText: rowText });
  }

  /** 행 내부의 액션 버튼 클릭. */
  async clickRowAction(rowText: string | RegExp, actionName: string | RegExp): Promise<void> {
    const row = this.getRowByText(rowText);
    await expect(row).toBeVisible();
    await row.getByRole('button', { name: actionName }).click();
  }

  /** 행 개수 검증. */
  async expectRowCount(count: number): Promise<void> {
    // header row 제외
    await expect(this.page.getByRole('row')).toHaveCount(count + 1);
  }

  /** 특정 행이 존재하는지 검증. */
  async expectRowExists(rowText: string | RegExp): Promise<void> {
    await expect(this.getRowByText(rowText)).toBeVisible();
  }
}
```

---

## NavigationHelper

탭, 브레드크럼, 라우팅 검증.

```ts
// e2e/helpers/NavigationHelper.ts
import { expect, type Page } from '@playwright/test';

export class NavigationHelper {
  constructor(private readonly page: Page) {}

  /** 탭 클릭. */
  async clickTab(tabName: string | RegExp): Promise<void> {
    await this.page.getByRole('tab', { name: tabName }).click();
  }

  /** URL이 패턴과 매칭되는지 검증. */
  async expectUrlMatches(pattern: string | RegExp): Promise<void> {
    await expect(this.page).toHaveURL(pattern);
  }

  /** 현재 활성화된 탭 검증. */
  async expectActiveTab(tabName: string | RegExp): Promise<void> {
    await expect(
      this.page.getByRole('tab', { name: tabName, selected: true }),
    ).toBeVisible();
  }

  /** 브레드크럼 항목 검증. */
  async expectBreadcrumb(items: string[]): Promise<void> {
    const breadcrumb = this.page.getByRole('navigation', { name: /breadcrumb|경로/i });
    for (const item of items) {
      await expect(breadcrumb.getByText(item)).toBeVisible();
    }
  }
}
```

---

## ToastHelper

Toast / Notification 검증.

```ts
// e2e/helpers/ToastHelper.ts
import { expect, type Page } from '@playwright/test';

export class ToastHelper {
  constructor(private readonly page: Page) {}

  /** 성공 토스트 검증. 메시지 지정 시 텍스트도 검증. */
  async expectSuccess(message?: string | RegExp): Promise<void> {
    const toast = this.page.getByRole('status').filter({ hasText: message ?? /./ });
    await expect(toast).toBeVisible();
  }

  /** 에러 토스트 검증. */
  async expectError(message?: string | RegExp): Promise<void> {
    const toast = this.page.getByRole('alert').filter({ hasText: message ?? /./ });
    await expect(toast).toBeVisible();
  }

  /** 토스트가 사라질 때까지 대기. */
  async waitForDismiss(): Promise<void> {
    await this.page.getByRole('status').waitFor({ state: 'hidden' });
  }
}
```

---

## Helper 확장 원칙

- **새 디자인 시스템 컴포넌트가 추가되면 Helper도 함께 추가**한다 (`FileUploadHelper`, `DatePickerHelper` 등).
- 메서드명은 **자연어에 가깝게** — `clickConfirm`, `expectSuccess`처럼 동사+의미.
- Helper 내부 selector는 항상 1·2순위(`getByRole`, `getByLabel`)를 우선한다. 3순위(`data-slot`)는 1·2순위로 불가능할 때만.
- **선언적 단언**을 권장 (`expect(...).toBeVisible()`)하고, 명령형 대기(`waitForSelector`)는 가급적 피한다.
- UI 변경 시 **Helper 내부만 수정**해도 spec/flow 전체가 복구되도록 설계 — 자가 복구의 핵심.

```diff
// 예: 버튼 텍스트가 '저장' → '등록'으로 바뀐 경우
class FormHelper {
-  async submit(label = '저장') {
+  async submit(label = '등록') {
    await this.page.getByRole('button', { name: label }).click();
  }
}
// spec의 form.submit() 호출은 그대로 통과
```
