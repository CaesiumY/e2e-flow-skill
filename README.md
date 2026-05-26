# e2e-flow-skill

> QA 인력이 없는 프론트엔드 팀에서, 한 마디 자연어로 Playwright E2E 테스트를 셋업·생성·자가복구·확장하는 Claude Code 스킬.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skill](https://img.shields.io/badge/skill-e2e--flow-blue)](./skills/e2e-flow/SKILL.md)
[![Phases](https://img.shields.io/badge/pipeline-4_phases-green)](#4단계-파이프라인)

자연어로 `"에이전트 생성 페이지에서 이름·설명 입력하고 저장하면 성공 토스트 뜨는지 확인하는 테스트 만들어줘"` 한 마디면 — 규칙 준수 spec/flow 코드가 나오고, 실행 후 실패하면 trace를 분석해 4가지 분류(UI_CHANGE / TEST_BUG / APP_BUG / ENV_ISSUE)로 자가 복구까지 시도합니다.

---

## 설치

**Linux / macOS / WSL / Git Bash**:

```bash
curl -fsSL https://raw.githubusercontent.com/CaesiumY/e2e-flow-skill/main/install.sh | bash
```

**Windows (PowerShell 5.1+ / 7+)**:

```powershell
irm https://raw.githubusercontent.com/CaesiumY/e2e-flow-skill/main/install.ps1 | iex
```

**Claude Code skills CLI** (있는 환경에서):

```bash
npx skills add CaesiumY/e2e-flow-skill
```

### 설치 옵션

| 옵션 | 의미 | 기본값 |
|---|---|---|
| `--target=project` (bash) / `-Target project` (PS) | 현재 프로젝트의 `./.claude/skills/` 에 설치 | `--target=global` (`~/.claude/skills/`) |
| `--ref=<tag\|branch>` (bash) / `-Ref <ref>` (PS) | 특정 태그/브랜치에 고정 | `main` |
| `--skill-dir=<path>` (bash) / `-SkillDir <path>` (PS) | 임의 디렉터리에 설치 | — |

**예시 — 프로젝트 로컬 + 특정 태그**:

```bash
curl -fsSL https://raw.githubusercontent.com/CaesiumY/e2e-flow-skill/main/install.sh | bash -s -- --target=project --ref=v1.0.0
```

```powershell
iex "& { $(irm https://raw.githubusercontent.com/CaesiumY/e2e-flow-skill/main/install.ps1) } -Target project -Ref v1.0.0"
```

설치 후 Claude Code를 재시작하면 스킬이 자동 로드됩니다.

---

## 무엇을 하는 스킬인가요?

Claude Code 안에서 자연어로 부르면 작동하는 **트리거 기반 스킬**입니다. 항상 켜져 있지 않고, 다음 표현이 감지되면 자동 발동합니다:

- **"Playwright 셋업해줘"** → 인프라 셋업 (Phase 1)
- **"이 페이지 테스트 만들어줘"** → 자연어 → 코드 변환 (Phase 2)
- **"테스트 깨졌어 고쳐줘"** → 자가 복구 루프 (Phase 3)
- **"VRT 붙여줘"** / **"E2E CI 워크플로우 추가해줘"** → 확장 (Phase 4)

스킬이 현재 프로젝트 상태(`playwright.config.*`, `e2e/helpers/`, 기존 테스트 수)를 자동 감지해 어느 페이즈로 들어갈지 결정합니다. **한 진입점, 자동 라우팅** 이 핵심입니다.

---

## Before / After

같은 요청 — *"에이전트 생성 페이지에서 이름·설명 입력하고 저장 → 모달 확인 → 성공 토스트 뜨는지 확인하는 테스트 만들어줘"*

**스킬 없이 AI가 작성** (저수준 API 조합, 일관성 부족):

```ts
test('에이전트 생성', async ({ page }) => {
  await page.goto('/ai-agent/create');
  await page.getByLabel('이름').fill('테스트 에이전트');
  await page.getByLabel('설명').fill('설명입니다');
  await page.getByRole('button', { name: '저장' }).click();
  await page.getByRole('button', { name: '생성' }).click();
  await expect(page.locator('.toast-success')).toBeVisible();
});
```

**e2e-flow 스킬 사용** (Helper 6종 + 규칙 준수, 자가 복구 통과):

```ts
// e2e/tests/agent/specs/create.spec.ts
test('에이전트 정상 생성', async ({ page, form, dialog, toast }) => {
  await page.goto('/ai-agent/create');
  await form.fillFields({
    '에이전트 이름': '테스트 에이전트',
    '설명': '테스트용 에이전트입니다',
  });
  await form.submit('저장');
  await dialog.clickConfirm('생성');
  await toast.expectSuccess();
});
```

UI가 변경되면 (예: 버튼 텍스트 `'저장'` → `'등록'`) **Helper 한 줄 수정**으로 전체 테스트가 복구됩니다. 자가 복구 루프가 이를 자동으로 시도합니다.

---

## 4단계 파이프라인

```
[입력 신호 감지] → [페이즈 라우팅] → [절차 실행] → [사용자 보고]
```

| Phase | 입력 신호 | 서브에이전트 | 산출물 |
|---|---|---|---|
| **1. 인프라 셋업** | `playwright.config.*` 없음 / "셋업해줘" | **Codebase Analyzer** (Explore, 1회) | Playwright 설정, Helper 6종, Fixture 자동주입, Mock 핸들러, 예시 spec/flow, AI 가이드 문서, `AGENTS.md`, `package.json` 스크립트 |
| **2. 테스트 생성** | 자연어 시나리오 입력 | — (메인 스레드) | `*.spec.ts` + `*-flows.ts` (+ mocks). 즉시 Phase 3 자동 연계 |
| **3. 자가 복구** | 테스트 실패 / "고쳐줘" | **Self-Healer** (general-purpose, 매 루프) | 분류된 패치 적용 또는 안전 보고. 최대 3회 |
| **4. 확장** | "VRT" / "CI" / "병렬화" / "shard" | — (메인 스레드) | `vrt.ts` 헬퍼, Dynamic Shard CI 워크플로우 |

---

## Helper 6종 (디자인 시스템 1:1 매핑)

| Helper | 매핑 컴포넌트 | 대표 메서드 |
|---|---|---|
| `DialogHelper` | Dialog / Modal | `waitForOpen`, `clickConfirm`, `close`, `expectTitle` |
| `FormHelper` | Form / Input | `fillFields`, `submit`, `expectErrors`, `expectFieldEditable` |
| `SelectHelper` | Select / Combobox | `selectByLabel`, `selectFirstOption`, `expectSelected` |
| `TableHelper` | DataTable | `getRowByText`, `clickRowAction`, `expectRowCount`, `expectRowExists` |
| `NavigationHelper` | Tabs / Breadcrumb / Routing | `clickTab`, `expectUrlMatches`, `expectActiveTab`, `expectBreadcrumb` |
| `ToastHelper` | Toast / Notification | `expectSuccess`, `expectError`, `waitForDismiss` |

새 디자인 시스템 컴포넌트가 추가되면 Helper도 함께 확장합니다. 모든 메서드는 자연어에 가까운 이름을 가지며, 내부적으로 Selector 우선순위 규칙을 강제합니다.

---

## Selector 우선순위

스킬이 생성·수정하는 모든 코드는 다음 우선순위를 따릅니다:

```
1순위: getByRole('button', { name: '저장' })          # ARIA role
2순위: getByLabel('이름') / getByPlaceholder('...')   # ARIA 속성
3순위: [data-slot="dialog-title"]                      # 디자인 시스템 기반
영역 스코핑: page.getByTestId('section').getByRole(...)
금지: getByText(/A|B|C/) 등 Strict Mode 위반 패턴
```

ARIA 우선이므로 접근성 개선이 부수 효과로 따라옵니다. 1·2순위로 잡을 수 없는 컴포넌트를 발견하면 스킬이 `data-slot` / `data-testid` 추가를 권장합니다.

상세 규칙: [`skills/e2e-flow/references/selector-priority.md`](./skills/e2e-flow/references/selector-priority.md)

---

## 자가 복구 4분류

테스트 실패 시 trace 스크린샷·에러 로그를 분석해 다음 4가지로 분류합니다:

| 분류 | 의미 | 스킬 행동 |
|---|---|---|
| **UI_CHANGE** | UI가 의도적으로 바뀌어 selector 불일치 | Helper/spec selector 자동 수정 |
| **TEST_BUG** | 테스트 코드 결함 (strict mode 위반, 대기 부족 등) | 코드 자동 수정 |
| **APP_BUG** | 앱의 실제 결함 | **수정 금지. 보고만** |
| **ENV_ISSUE** | 서버 미기동, 네트워크 문제 등 | **수정 금지. 보고만** |

**안전 가드**: APP_BUG / ENV_ISSUE는 절대 자동 수정하지 않습니다 — 앱 버그를 테스트 수정으로 덮는 위험을 차단합니다. 또한 `confidence < 0.5`인 패치는 자동 적용을 거부하고 사용자 검토 요청, 최대 3회 시도 한도가 적용됩니다.

상세 기준: [`skills/e2e-flow/references/failure-classification.md`](./skills/e2e-flow/references/failure-classification.md)

---

## 저장소 레이아웃

```
e2e-flow-skill/
├── README.md                         ← 이 파일
├── LICENSE
├── install.sh, install.ps1           ← 한 줄 설치 스크립트
├── CONTRIBUTING.md                   ← 기여 가이드
└── skills/
    └── e2e-flow/                     ← 스킬 본체 (single source of truth)
        ├── SKILL.md                  ← 진입점 (상태 감지 + 페이즈 라우팅)
        ├── references/               ← 절차서 + 규칙
        │   ├── phase-1-setup.md
        │   ├── phase-2-generate.md
        │   ├── phase-3-self-heal.md
        │   ├── phase-4-enhance.md
        │   ├── selector-priority.md
        │   ├── failure-classification.md
        │   ├── helper-templates.md
        │   └── playwright-fixtures.md
        └── assets/
            ├── templates/            ← 코드 템플릿 (.tmpl)
            │   ├── playwright.config.ts.tmpl
            │   ├── fixtures.ts.tmpl
            │   ├── apiMockHandlers.ts.tmpl
            │   ├── spec.example.ts.tmpl
            │   ├── flows.example.ts.tmpl
            │   ├── helpers/{Dialog,Form,Select,Table,Navigation,Toast}Helper.ts.tmpl
            │   └── ci/playwright-dynamic-shard.yml.tmpl
            └── prompts/              ← 서브에이전트 프롬프트
                ├── codebase-analyzer.md
                └── self-healer.md
```

설치 시 `skills/e2e-flow/` 하위만 `~/.claude/skills/e2e-flow/` 로 복사됩니다. 루트의 install 스크립트와 README는 복사 대상이 아닙니다.

---

## 동작 요건

- **Claude Code** (Skill 지원 버전)
- 대상 프로젝트: **Node.js**, 패키지 매니저 무관 (pnpm / npm / yarn / bun 자동 감지)
- **Playwright 1.40+** 권장 (Fixture, trace, `getByRole` 등 사용)
- **Git** 권장 (자가 복구 패치 적용 전후 diff 확인 용이)

---

## 커스터마이즈

| 커스터마이즈 대상 | 위치 |
|---|---|
| 스킬 트리거 키워드 | `skills/e2e-flow/SKILL.md` 의 frontmatter `description` |
| Helper 종류·메서드 | `skills/e2e-flow/references/helper-templates.md` + `skills/e2e-flow/assets/templates/helpers/` |
| Selector 우선순위 규칙 | `skills/e2e-flow/references/selector-priority.md` |
| 실패 분류 기준 | `skills/e2e-flow/references/failure-classification.md` |
| 페이즈 1 산출물 템플릿 | `skills/e2e-flow/assets/templates/*.tmpl` |
| 서브에이전트 프롬프트 | `skills/e2e-flow/assets/prompts/` |
| CI 워크플로우 | `skills/e2e-flow/assets/templates/ci/playwright-dynamic-shard.yml.tmpl` |

스킬은 단일 출처(SoT) 구조라 규칙을 한 곳만 고쳐도 전 페이즈에 일관되게 반영됩니다.

---

## 한계와 운영 가이드

- **VRT는 CI 게이트로 강제하지 않습니다.** OS·브라우저 렌더링 차이가 false-positive를 만들어 의미 있는 변화도 묻히기 때문. 로컬에서 `pnpm test:vrt` 로 검토용으로만 사용합니다.
- **자가 복구가 모든 실패를 고치진 않습니다.** APP_BUG / ENV_ISSUE는 의도적으로 수정하지 않습니다 — 앱 버그를 테스트 수정으로 덮는 것을 막기 위함.
- **Helper는 디자인 시스템 변경에 동기화 필요**합니다. 버튼 텍스트나 ARIA 구조가 바뀌면 Helper 내부 한 줄 수정으로 전체 테스트가 복구되도록 설계되어 있습니다.
- **Claude Code 전용**입니다. Cursor/Cline/Gemini 등 다른 AI 도구로의 이식은 워크플로우의 서브에이전트 의존성 때문에 직접 지원하지 않습니다 (어댑터 PR은 환영).

---

## 기여

[CONTRIBUTING.md](./CONTRIBUTING.md) 참조. PR 환영 — 특히:

- 새 Helper (예: `FileUploadHelper`, `DatePickerHelper`)
- 디자인 시스템별 selector 패턴 (shadcn/ui, MUI, Chakra 등)
- 자가 복구 분류 기준 개선
- CI 워크플로우 변형 (CircleCI, GitLab CI 어댑터 등)

## License

MIT — [LICENSE](./LICENSE) 참조.
