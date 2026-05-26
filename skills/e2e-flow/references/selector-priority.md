# Selector 우선순위 규칙

스킬이 생성·수정하는 모든 Playwright locator는 다음 순서를 따른다. AI가 selector를 자유롭게 선택하면 같은 페이지의 비슷한 요소를 잘못 잡거나 매번 다른 스타일로 코드를 생성하기 때문에, 명시적 규칙으로 일관성을 강제한다.

## 우선순위 3단계

### 1순위 — ARIA Role

가장 견고하다. 접근성 트리에 기반하므로 DOM 구조 변경에 영향을 적게 받는다.

```ts
// 버튼
await page.getByRole('button', { name: '저장' }).click();

// 링크
await page.getByRole('link', { name: '대시보드' }).click();

// 헤딩
await expect(page.getByRole('heading', { name: '에이전트 생성' })).toBeVisible();

// 모달
const dialog = page.getByRole('dialog', { name: '삭제 확인' });
```

**언제 쓰는가**: 시멘틱 HTML 요소를 다룰 때 항상.

### 2순위 — ARIA 속성 (Label / Placeholder)

폼 입력은 1순위 role(`textbox`)로 잡기 어려운 경우가 많아 label/placeholder를 사용한다.

```ts
// 폼 입력 (label 권장)
await page.getByLabel('이름').fill('테스트');
await page.getByLabel('비밀번호').fill('***');

// 라벨이 없는 경우 placeholder
await page.getByPlaceholder('-제외 10자리 입력').fill('1234567890');
```

**언제 쓰는가**: `<label for="...">` 가 있거나, placeholder가 충분히 식별 가능할 때.

### 3순위 — data-slot 또는 data-testid

디자인 시스템 컴포넌트의 내부 구조를 가리켜야 할 때만 사용한다. 1·2순위로 잡을 수 없는 경우의 최후 수단.

```ts
// 디자인 시스템이 data-slot을 제공하는 경우 (shadcn/ui 패턴)
await page.locator('[data-slot="dialog-title"]').isVisible();

// 영역 식별용 (사용자 정의)
await page.getByTestId('datasource-content');
```

**언제 쓰는가**: 시멘틱 마크업으로 충분히 구분되지 않는 컨테이너/래퍼를 가리킬 때.

---

## 영역 스코핑 (Area Scoping)

같은 페이지에 비슷한 요소가 여러 개 있으면, 영역을 먼저 좁힌 뒤 그 안에서 다시 1·2순위 selector로 잡는다.

```ts
// ❌ 의도: 데이터소스 목록에서 '폴더 생성'
// 실제: LNB의 다른 '폴더 생성'을 잡을 수 있음
await page.getByRole('button', { name: '폴더 생성' }).click();

// ✅ 영역 스코핑
const dataSourceArea = page.getByTestId('datasource-content');
await dataSourceArea.getByRole('button', { name: '폴더 생성' }).click();
```

**스코프 후보 우선순위**:
1. `getByRole('region', { name: ... })` — 시멘틱 region이 있는 경우
2. `getByRole('dialog' | 'tabpanel' | 'navigation', ...)` — 시멘틱 컨테이너
3. `getByTestId(...)` — 사용자 정의 영역

---

## 금지 패턴

### Strict Mode 위반: OR 매칭

`getByText(/A|B|C/)`처럼 여러 후보를 한 번에 매칭하면 Playwright Strict Mode가 "여러 요소가 매칭됨" 에러를 던진다.

```ts
// ❌ Strict Mode 위반
await page.getByText(/저장|등록|확인/).click();

// ❌ 에러 메시지를 한 번에 매칭
await expect(page.getByText(/필수|올바르지|길이/)).toBeVisible();

// ✅ 개별 locator로 각각 검증
await expect(page.getByText('이름은 필수입니다')).toBeVisible();
await expect(page.getByText('이메일이 올바르지 않습니다')).toBeVisible();
```

### nth() / first() 남용

요소의 의미를 잃는다. 영역 스코핑이나 더 구체적인 selector를 먼저 시도한다.

```ts
// ❌ 의미 불명
await page.getByRole('button').first().click();

// ✅ 영역 + role + 이름
await page.getByRole('toolbar').getByRole('button', { name: '추가' }).click();
```

### 텍스트 노드를 클릭

텍스트가 변하면 깨진다. role + name 조합으로 의미를 고정한다.

```ts
// ❌ 텍스트 그 자체를 찾음
await page.getByText('확인').click();

// ✅ 의미 명시
await page.getByRole('button', { name: '확인' }).click();
```

### CSS 클래스 의존

빌드 도구가 클래스명을 해시할 수 있다. 절대 의존하지 않는다.

```ts
// ❌ 클래스명은 빌드 결과물에 영향받음
await page.locator('.MuiButton-primary').click();

// ✅ 의미 기반
await page.getByRole('button', { name: '제출' }).click();
```

---

## data-testid 추가 권장 시나리오

Phase 2(테스트 생성)와 Phase 3(자가 복구) 중 1·2순위로 잡을 수 없는 컴포넌트를 만나면, 다음 우선순위로 사용자에게 권장한다.

1. **컴포넌트가 시멘틱 HTML을 안 쓰는 경우** → 컴포넌트에 적절한 `role` 추가 권장
2. **같은 시멘틱 요소가 영역 식별 없이 반복되는 경우** → 컨테이너에 `data-testid` 추가 권장
3. **디자인 시스템 슬롯 식별** → 디자인 시스템 컴포넌트가 `data-slot`을 자동으로 부여하면 그대로 사용

권장 시에는 수정 diff를 함께 제시한다.

```ts
// 예: 발견 후 권장
// 발견: e2e/tests/dashboard/specs/main.spec.ts 의 다음 코드가 영역 식별 없이 동일 role을 잡음
//       await page.getByRole('button', { name: '편집' }).click();
//
// 권장 패치:
// components/UserList.tsx
- <div className="user-card">
+ <div className="user-card" data-testid="user-card">

// 테스트:
- await page.getByRole('button', { name: '편집' }).click();
+ await page.getByTestId('user-card').getByRole('button', { name: '편집' }).click();
```

---

## 요약 의사 결정 트리

```
요소를 잡아야 함
  ├─ 같은 페이지에 비슷한 요소 여럿?
  │    └─ 예 → 영역 스코프 먼저 좁힌다
  │
  ├─ 시멘틱 요소(button, link, heading, dialog ...)?
  │    └─ 예 → 1순위: getByRole(role, { name })
  │
  ├─ 폼 입력?
  │    ├─ label 있음 → 2순위: getByLabel
  │    └─ placeholder만 있음 → 2순위: getByPlaceholder
  │
  └─ 그 외 컨테이너/래퍼?
       └─ 3순위: [data-slot=...] 또는 getByTestId
            └─ data-* 누락이면 사용자에게 추가 권장
```
