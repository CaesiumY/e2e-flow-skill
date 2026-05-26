---
name: e2e-flow
description: Playwright 기반 프론트엔드 E2E 테스트 파이프라인. 자연어 시나리오를 규칙 준수 spec/flow 코드로 변환하고, 실패 시 trace 분석으로 자가 복구한다. 사용 시점 - "E2E 테스트 추가해줘", "Playwright 셋업해줘", "이 페이지 테스트 만들어줘", "테스트가 깨졌어 고쳐줘", "VRT 붙여줘", "E2E CI 최적화해줘", "Playwright shard 설정해줘".
---

# e2e-flow

프론트엔드 프로젝트의 E2E 테스트를 도입·운영하는 4단계 파이프라인. 한 진입점에서 프로젝트 상태를 감지해 적절한 페이즈로 라우팅한다.

## 파이프라인 개요

- **Phase 1 — 인프라 셋업**: Playwright + Helper 9종 + Selector 규칙 + specs/flows 구조 생성
- **Phase 2 — 테스트 생성**: 자연어 시나리오를 규칙 준수 spec/flow 코드로 변환
- **Phase 3 — 자가 복구**: 실행 실패 시 trace를 분석해 4가지 분류 → 자동 패치 (최대 3회)
- **Phase 4 — 확장**: VRT, Dynamic Shard CI 등 운영 단계 도구

각 페이즈의 상세 절차는 `references/phase-N-*.md`에 분리되어 있다. 본 문서는 라우팅과 공통 규칙만 담는다.

---

## 진입 시 첫 동작 (반드시 순서대로)

### Step 1. 상태 감지

다음 4개 신호를 Glob / Read로 빠르게 수집한다:

1. `playwright.config.{ts,js,mjs,cjs}` 존재 여부 → 인프라 셋업 완료 여부
2. `e2e/helpers/*Helper.ts` 파일 개수 → Helper 셋업 완료 여부 (목표 6개)
3. `e2e/tests/**/*.spec.ts` 개수 → 기존 테스트 보유 여부
4. 사용자 입력 키워드 (셋업/추가/생성/고쳐/실패/VRT/CI/병렬화/shard)

### Step 2. 페이즈 라우팅

| 상태 / 입력 신호 | 진입 페이즈 | 후속 액션 |
|---|---|---|
| playwright.config 없음 | **Phase 1** | `references/phase-1-setup.md` 읽고 절차 수행 |
| 인프라 있음 + 자연어 시나리오 입력 | **Phase 2** (→ Phase 3 자동 연계) | `references/phase-2-generate.md` 읽고 절차 수행 |
| "테스트 깨졌어 / 고쳐줘 / 실패" + 실패 출력 첨부 | **Phase 3** | `references/phase-3-self-heal.md` 읽고 절차 수행 |
| "VRT / CI / 워크플로우 / 병렬화 / shard" 키워드 | **Phase 4** | `references/phase-4-enhance.md` 읽고 절차 수행 |
| 모호함 | — | `AskUserQuestion`으로 4지선다 확인 |

### Step 3. 페이즈 절차 실행

선택된 페이즈의 절차서를 Read한 뒤, 그 안의 지침을 그대로 따른다. 각 절차서는 자기완결적이다.

---

## 공통 규칙 (모든 페이즈 공유)

### Selector 우선순위

생성·수정하는 모든 코드는 반드시 다음 순서를 따른다:

```
1순위: getByRole('button', { name: '저장' })
2순위: getByLabel('이름') / getByPlaceholder('-제외 10자리')
3순위: [data-slot="dialog-title"]  (디자인 시스템 기반 속성)
영역 스코핑: page.getByTestId('section').getByRole(...)
금지: getByText(/A|B|C/) 등 Strict Mode 위반 패턴
```

상세 규칙과 안티패턴은 `references/selector-priority.md`.

### 파일 구조 컨벤션

```
e2e/
├── fixtures.ts                       # Helper 자동 주입 (Playwright Fixture)
├── helpers/                          # 디자인 시스템 1:1 매핑
│   ├── DialogHelper.ts
│   ├── FormHelper.ts
│   ├── SelectHelper.ts
│   ├── TableHelper.ts
│   ├── NavigationHelper.ts
│   ├── ToastHelper.ts
│   ├── CheckboxHelper.ts
│   ├── RadioGroupHelper.ts
│   └── FileUploadHelper.ts
├── mocks/
│   └── apiMockHandlers.ts            # fixture 매처 기반 모킹
├── shared/
│   └── sequences/                    # 공통 선행 동작 (로그인 등)
└── tests/{도메인}/
    ├── specs/                        # 사용자 행동 (자연어에 가까운 흐름)
    └── flows/                        # 행동의 구현체 (Helper 조합)
```

### 자연어 → 코드 매핑 (Phase 2·3 공통)

| 자연어 표현 | 생성/제안할 코드 |
|---|---|
| "X 입력하고" | `await form.fillFields({ X: ... })` |
| "Y 버튼 누르고" | `await form.submit('Y')` |
| "Z 모달에서 확인" | `await dialog.waitForOpen(); await dialog.clickConfirm('Z')` |
| "성공 토스트 확인" | `await toast.expectSuccess()` |
| "에러 토스트 확인" | `await toast.expectError()` |
| "탭 전환" | `await navigation.clickTab('탭이름')` |
| "테이블 X 행 클릭" | `await table.clickRowAction('X', 'action')` |
| "옵션 선택" | `await select.selectByLabel('레이블', '값')` |
| "URL 변경 확인" | `await navigation.expectUrlMatches(/.../)` |
| "X 체크해줘" / "X 동의" | `await checkbox.check('X')` |
| "X 체크 해제" | `await checkbox.uncheck('X')` |
| "X, Y, Z 모두 체크" | `await checkbox.checkMultiple(['X','Y','Z'])` |
| "결제 방법으로 신용카드 선택" | `await radioGroup.selectByLabel('결제 방법','신용카드')` |
| "신분증 첨부" | `await fileUpload.selectFiles('신분증', [path.join(__dirname,'fixtures/id.png')])` |
| "첨부한 파일 제거" | `await fileUpload.removeFile('id.png')` |

### 서브에이전트 사용 정책

- **Codebase Analyzer** (Phase 1 진입 시 1회): `assets/prompts/codebase-analyzer.md` 를 프롬프트로 Explore 서브에이전트 디스패치
- **Self-Healer** (Phase 3 루프 매 회): `assets/prompts/self-healer.md` 를 프롬프트로 general-purpose 서브에이전트 디스패치
- 그 외 모든 작업은 메인 스레드에서 직접 수행 (디버깅 용이성 + 토큰 효율)

### 보고 원칙

- **APP_BUG / ENV_ISSUE 분류 시**: 절대 수정하지 않고 즉시 사용자 보고
- **자가 복구 3회 실패 시**: 최종 trace 디렉터리 경로, 마지막 가설, 적용한 패치 이력을 함께 보고
- **신규 도메인 추가 시**: Selector 우선순위 1·2순위로 잡을 수 없는 컴포넌트 발견하면 `data-slot` / `data-testid` 추가 권장 (수정 diff도 함께 제시)
- **테스트 통과 시**: 어떤 파일이 생성/수정되었는지 요약 후 다음 단계 안내 (Phase 3 자동 진입 or 추가 시나리오 요청)

---

## 페이즈별 진입 체크리스트 (TaskCreate로 분해)

큰 페이즈에 진입하면 다음 항목을 작업 태스크로 분해해 추적한다.

**Phase 1 — 인프라 셋업**
1. Codebase Analyzer 디스패치
2. `playwright.config.ts` 생성
3. `e2e/helpers/` 9개 Helper 생성
4. `e2e/fixtures.ts` 생성 (Helper 자동 주입)
5. `e2e/mocks/apiMockHandlers.ts` 생성
6. `e2e/tests/example/` specs + flows 예시 1쌍 생성
7. `e2e/shared/sequences/` 디렉터리 생성
8. `docs/ai/skills/e2e-flow-generator.md` 프로젝트별 가이드 생성
9. `AGENTS.md` 등록 항목 추가
10. `package.json` 스크립트 추가 (`test:e2e`, `test:vrt`, `test:vrt-update`)

**Phase 2 — 테스트 생성**
1. 자연어 입력 파싱 (도메인, 시작 페이지, 액션 시퀀스, 검증)
2. 기존 Helper 카탈로그 로드 (`e2e/helpers/`)
3. 기존 spec/flow 패턴 1~2개 학습
4. spec 파일 생성 (`e2e/tests/{도메인}/specs/{시나리오}.spec.ts`)
5. flow 파일 생성 (`e2e/tests/{도메인}/flows/{시나리오}-flows.ts`)
6. 필요 시 mock 추가 (`e2e/mocks/{도메인}-mocks.ts`)
7. `data-testid` 누락 검토
8. → Phase 3 자동 진입

**Phase 3 — 자가 복구 (루프, 최대 3회)**
1. 대상 테스트 실행
2. 실패 시 trace/screenshot/에러 로그 수집
3. Self-Healer 서브에이전트 디스패치
4. 분류 검토
5. UI_CHANGE / TEST_BUG → 패치 적용 후 1번으로 / APP_BUG / ENV_ISSUE → 보고하고 종료
6. 3회 도달 시 최종 보고

**Phase 4 — 확장**
1. 확장 종류 선택 (VRT / Dynamic Shard CI / 알림)
2. 해당 템플릿 복사 + 치환
3. 사용자에게 변경 사항과 운영 가이드 요약 출력

---

## 참조 문서 인덱스

| 문서 | 내용 |
|---|---|
| `references/phase-1-setup.md` | Phase 1 절차 (Analyzer 디스패치, 템플릿 복사, 치환 규칙) |
| `references/phase-2-generate.md` | Phase 2 절차 (자연어 파싱, Helper 카탈로그, 패턴 학습) |
| `references/phase-3-self-heal.md` | Phase 3 절차 (실행, Healer 오케스트레이션, 패치 적용) |
| `references/phase-4-enhance.md` | Phase 4 절차 (VRT, Dynamic Shard CI) |
| `references/helper-templates.md` | 9개 Helper 완성 코드 |
| `references/selector-priority.md` | Selector 우선순위와 안티패턴 |
| `references/failure-classification.md` | Self-Healer 4분류 기준 |
| `references/playwright-fixtures.md` | Fixture 자동 주입 패턴 |
| `assets/templates/` | 복사용 파일 템플릿 (config, fixtures, helpers, mocks, ci) |
| `assets/prompts/` | 서브에이전트 프롬프트 (analyzer, healer) |
