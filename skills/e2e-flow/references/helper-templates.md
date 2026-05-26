# Helper 9종 완성 코드

디자인 시스템 컴포넌트와 1:1 매핑되는 Helper 9개. Phase 1에서 `assets/templates/helpers/*.tmpl` 로부터 프로젝트의 `e2e/helpers/` 에 복사·치환된다.

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

## CheckboxHelper

체크박스·토글의 체크/해제/검증. `setChecked()` 기반이라 멱등 처리.

```ts
// e2e/helpers/CheckboxHelper.ts
import { expect, type Page, type Locator } from '@playwright/test';

export class CheckboxHelper {
  constructor(private readonly page: Page) {}

  /** 체크 — setChecked(true)로 멱등 처리. */
  async check(label: string | RegExp): Promise<void> {
    await this.locate(label).setChecked(true);
  }

  /** 체크 해제 — setChecked(false)로 멱등 처리. */
  async uncheck(label: string | RegExp): Promise<void> {
    await this.locate(label).setChecked(false);
  }

  /** 현재 상태 반전 ("X 토글" 자연어). */
  async toggle(label: string | RegExp): Promise<void> {
    await this.locate(label).click();
  }

  /** 체크 상태 검증. 기본값 true. */
  async expectChecked(label: string | RegExp, checked = true): Promise<void> {
    const locator = this.locate(label);
    if (checked) await expect(locator).toBeChecked();
    else await expect(locator).not.toBeChecked();
  }

  /** 여러 항목 일괄 체크 (순차 setChecked). */
  async checkMultiple(labels: string[]): Promise<void> {
    for (const label of labels) {
      await this.locate(label).setChecked(true);
    }
  }

  /** ARIA role=checkbox 기반 매칭. native input과 button[role=checkbox] 모두 지원. */
  private locate(label: string | RegExp): Locator {
    return this.page.getByRole('checkbox', { name: label });
  }
}
```

---

## RadioGroupHelper

라디오 그룹의 옵션 선택과 검증. `<fieldset><legend>` 또는 `role="radiogroup" aria-label`로 그룹이 노출됨을 전제.

```ts
// e2e/helpers/RadioGroupHelper.ts
import { expect, type Page } from '@playwright/test';

export class RadioGroupHelper {
  constructor(private readonly page: Page) {}

  /** 그룹 안에서 옵션 선택. "결제 방법으로 신용카드 선택" 자연어에 매핑. */
  async selectByLabel(groupLabel: string, optionLabel: string | RegExp): Promise<void> {
    const group = this.page.getByRole('radiogroup', { name: groupLabel });
    await expect(group).toBeVisible();
    await group.getByRole('radio', { name: optionLabel }).check();
  }

  /** 현재 선택된 옵션 검증. */
  async expectSelected(groupLabel: string, expectedOption: string | RegExp): Promise<void> {
    const group = this.page.getByRole('radiogroup', { name: groupLabel });
    await expect(group.getByRole('radio', { name: expectedOption })).toBeChecked();
  }
}
```

---

## FileUploadHelper

`<input type="file">` 또는 디자인 시스템 업로더의 파일 첨부·검증·제거. `setInputFiles`는 hidden input에도 동작.

```ts
// e2e/helpers/FileUploadHelper.ts
import { expect, type Page } from '@playwright/test';

export class FileUploadHelper {
  constructor(private readonly page: Page) {}

  /** label로 식별된 파일 입력에 파일 첨부. filePaths는 절대 경로 권장. */
  async selectFiles(label: string, filePaths: string[]): Promise<void> {
    await this.page.getByLabel(label).setInputFiles(filePaths);
  }

  /** 업로드 후 표시되는 파일명 검증. */
  async expectUploadedFile(name: string | RegExp): Promise<void> {
    await expect(this.page.getByText(name)).toBeVisible();
  }

  /** 업로드된 파일 개수 검증. role=listitem 마크업 가정. */
  async expectFileCount(count: number): Promise<void> {
    await expect(this.page.getByRole('listitem').filter({
      hasText: /\.(png|jpe?g|pdf|docx?|xlsx?|csv|zip|gif|webp)$/i,
    })).toHaveCount(count);
  }

  /** 특정 파일의 삭제/제거 버튼 클릭. */
  async removeFile(name: string | RegExp): Promise<void> {
    const fileRow = this.page.getByRole('listitem').filter({ hasText: name });
    await fileRow.getByRole('button', { name: /삭제|제거|remove|delete/i }).click();
  }
}
```

사용 예 — fixture로 받아 자연어에 가까운 흐름:
```ts
test('계약 신분증 첨부', async ({ page, fileUpload, toast }) => {
  await page.goto('/contracts/123/identity');
  await fileUpload.selectFiles('신분증', [path.join(__dirname, 'fixtures/id-card.png')]);
  await fileUpload.expectUploadedFile('id-card.png');
  await toast.expectSuccess();
});
```

---

## Helper 확장 원칙

- **새 디자인 시스템 컴포넌트가 추가되면 Helper도 함께 추가**한다 (예: `DatePickerHelper`, `PaginationHelper`, `SearchHelper` — Tier B 후보). v0.2.0에서 `CheckboxHelper`, `RadioGroupHelper`, `FileUploadHelper` Tier A 3종이 추가됨.
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
