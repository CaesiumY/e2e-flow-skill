# Phase 4 — 확장 절차

VRT(시각적 회귀 테스트)와 Dynamic Shard CI를 추가하는 페이즈. **메인 스레드만 사용** (서브에이전트 불필요, 결정론적 템플릿 작업).

사용자 입력 키워드:
- "VRT", "스크린샷 테스트" → 4.1 VRT 추가
- "CI", "워크플로우", "GitHub Actions", "병렬화", "shard" → 4.2 Dynamic Shard CI 추가
- "Slack/Mattermost 알림" → 4.3 알림 추가 (선택)

여러 키워드가 동시에 오면 차례로 모두 실행.

---

## 4.1 VRT 추가

### 4.1.1 사용자 의도 확인

`AskUserQuestion`으로 다음을 묻는다:

1. VRT를 CI 게이트로 강제할지? → **권장: 아니오** (OS/브라우저 차이로 false-positive 위험)
2. 기본 viewport (데스크탑/모바일/둘 다)?

### 4.1.2 파일 생성/수정

| 작업 | 대상 |
|---|---|
| `takeVrtSnapshot()` 헬퍼 추가 | `e2e/helpers/vrt.ts` (신규) |
| `playwright.config.ts` VRT 옵션 추가 | `expect.toHaveScreenshot` 기본값 |
| `package.json` 스크립트 확인 | Phase 1에서 이미 `test:vrt`, `test:vrt-update` 추가됨 |
| 예시 VRT 테스트 추가 | `e2e/tests/example/specs/landing.vrt.spec.ts` |

### 4.1.3 vrt.ts 핵심

```ts
// e2e/helpers/vrt.ts
import { expect, type Page } from '@playwright/test';

interface VrtOptions {
  fullPage?: boolean;
  mask?: string[];          // selector 배열 — 동적 영역 가리기
  threshold?: number;       // 기본 0.2
}

export async function takeVrtSnapshot(
  page: Page,
  name: string,
  options: VrtOptions = {},
) {
  // 폰트/이미지 로드 대기
  await page.evaluate(() => document.fonts.ready);
  await page.waitForLoadState('networkidle');

  // 애니메이션 정지 (선택)
  await page.addStyleTag({
    content: `*, *::before, *::after { animation: none !important; transition: none !important; }`,
  });

  const maskLocators = (options.mask ?? []).map((s) => page.locator(s));

  await expect(page).toHaveScreenshot(`${name}.png`, {
    fullPage: options.fullPage ?? true,
    mask: maskLocators,
    threshold: options.threshold ?? 0.2,
    maxDiffPixelRatio: 0.005,
  });
}
```

### 4.1.4 예시 VRT 테스트

```ts
// e2e/tests/example/specs/landing.vrt.spec.ts
import { test } from '../../../fixtures';
import { takeVrtSnapshot } from '../../../helpers/vrt';

test('랜딩 페이지 @vrt', async ({ page }) => {
  await page.goto('/');
  await takeVrtSnapshot(page, 'landing', {
    mask: ['[data-dynamic="true"]'],
  });
});
```

`@vrt` 태그가 핵심. Phase 1에서 추가된 스크립트는 이를 기준으로 VRT를 분리한다.

### 4.1.5 사용자 보고

```
✅ VRT 추가 완료

생성/수정:
- e2e/helpers/vrt.ts (takeVrtSnapshot)
- e2e/tests/example/specs/landing.vrt.spec.ts
- playwright.config.ts (toHaveScreenshot 기본값)

운영 가이드:
- 로컬에서 검토용으로 실행: pnpm test:vrt
- 의도된 변경 후 스냅샷 업데이트: pnpm test:vrt-update
- 스냅샷 파일은 git에 커밋 (e2e/**/*-snapshots/)

⚠️ VRT는 CI 게이트로 강제하지 않습니다.
   OS·브라우저 렌더링 차이로 인한 false-positive를 피하기 위함입니다.
```

---

## 4.2 Dynamic Shard CI 추가

### 4.2.1 사용자 의도 확인

`AskUserQuestion`:

1. 트리거 — "모든 PR / 라벨 기반 / 스케줄 / 셋 다"?
2. 노드 버전 (`.nvmrc` 또는 `package.json` engines에서 감지)
3. 빌드 명령 (`pnpm build` / `npm run build` / 감지된 패키지 매니저)

### 4.2.2 파일 생성

`.github/workflows/playwright.yml` 을 `assets/templates/ci/playwright-dynamic-shard.yml.tmpl` 로부터 생성. 치환 변수:

- `{{PACKAGE_MANAGER}}` — pnpm/npm/yarn/bun
- `{{PW_EXEC}}` — 로컬 playwright 바이너리 실행 프리픽스. 매니저별로 다르다: pnpm → `pnpm exec`, npm → `npm exec`, yarn → `yarn exec`, **bun → `bunx`** (bun 은 `bun exec` 를 지원하지 않으므로 `bunx` 를 쓴다). `{{PACKAGE_MANAGER}} exec` 로 뭉뚱그리지 말 것.
- `{{INSTALL_CMD}}` — `pnpm install --frozen-lockfile` / `npm ci` / `yarn install --frozen-lockfile` / `bun install --frozen-lockfile`
- `{{BUILD_CMD}}` — `pnpm build` 등
- `{{NODE_VERSION}}` — `20` (기본) 또는 감지값
- `{{TRIGGER_BLOCK}}` — 템플릿의 `on:` 블록 전체(헤더 `on:` 포함)를 대체하는 자리. 4.2.1에서 받은 사용자 선택에 따라 아래 4가지 조각 중 하나를 그대로 삽입한다. 조각은 칼럼 0의 `on:`부터 시작하므로 들여쓰기를 바꾸지 말고 그대로 붙여넣을 것.
- `{{FILTER_CONDITION}}` — `filter` job의 `if:` 값을 대체하는 자리(한 줄 표현식 또는 `true`). **반드시 `{{TRIGGER_BLOCK}}`과 같은 선택지의 짝 값을 사용한다** — 트리거 조각만 바꾸고 이 값을 그대로 두면(또는 그 반대) 라벨 필드가 없는 이벤트에서 `filter`가 항상 skip되어 build/generate-shards-matrix까지 연쇄로 skip되고 워크플로우가 조용히 아무 것도 실행하지 않는다.

**트리거 선택지별 치환 조각 — `{{TRIGGER_BLOCK}}`과 `{{FILTER_CONDITION}}`은 항상 같은 번호의 값을 짝으로 사용한다** (4가지 모두 `workflow_dispatch:` 공통 포함):

① 모든 PR

`{{TRIGGER_BLOCK}}`:
```yaml
on:
  pull_request:   # 모든 PR 이벤트(open/synchronize/reopen)에서 트리거
  workflow_dispatch:   # 수동 실행
```

`{{FILTER_CONDITION}}`: `true`
(open/synchronize/reopened 이벤트에는 `github.event.label` 필드 자체가 없으므로 라벨 게이트를 걸면 항상 false가 되어 워크플로우가 skip된다 — 게이트 없이 항상 통과시킨다.)

② 라벨 기반 (기존 기본값)

`{{TRIGGER_BLOCK}}`:
```yaml
on:
  pull_request:
    types: [labeled]   # 'e2e' 또는 'release' 라벨 추가 시 트리거
  workflow_dispatch:   # 수동 실행
```

`{{FILTER_CONDITION}}`:
```
github.event_name != 'pull_request' || github.event.label.name == 'e2e' || github.event.label.name == 'release'
```
(labeled 이벤트에만 트리거되므로 `github.event.label`이 항상 존재 — 붙은 라벨이 e2e/release일 때만 통과, workflow_dispatch로 수동 실행 시에는 첫 절에서 무조건 통과.)

③ 스케줄

`{{TRIGGER_BLOCK}}`:
```yaml
on:
  workflow_dispatch:   # 수동 실행
  schedule:
    - cron: '0 22 * * *'   # 매일 KST 07:00 (UTC 22:00) 실행
```

`{{FILTER_CONDITION}}`: `true`
(pull_request 트리거 자체가 없으므로 라벨 게이트가 애초에 무의미 — 항상 통과시킨다.)

④ 셋 다

`{{TRIGGER_BLOCK}}`:
```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened, labeled]   # 모든 PR 이벤트 + 라벨로도 수동 재실행 가능
  workflow_dispatch:   # 수동 실행
  schedule:
    - cron: '0 22 * * *'   # 매일 KST 07:00 (UTC 22:00) 실행
```

`{{FILTER_CONDITION}}`: `true`
(open/synchronize/reopened로 이미 모든 PR이 포함되므로 라벨 게이트는 무의미 — `labeled` 타입은 게이트 조건이 아니라 "라벨을 추가/변경해 수동으로 재실행"하는 용도로만 남겨둔 것이다.)

### 4.2.3 워크플로우 구조 (요약)

```yaml
name: E2E Tests

# 실제 템플릿 파일(ci/playwright-dynamic-shard.yml.tmpl)에서 on: 블록 전체는
# {{TRIGGER_BLOCK}} 플레이스홀더 한 줄이고, filter job의 if: 값은 {{FILTER_CONDITION}}
# 플레이스홀더다 (치환 전). 아래는 4.2.2 ②(라벨 기반, 기존 기본값) 선택 시 치환된
# 실제 모습이다 — 다른 선택지는 4.2.2의 짝 조각(①③④) 참고.
on:
  pull_request:
    types: [labeled]   # e2e/release 라벨 시 실행
  workflow_dispatch:   # 수동 실행

jobs:
  filter:
    # {{TRIGGER_BLOCK}}과 짝인 {{FILTER_CONDITION}}으로 트리거 조건을 게이트
    # (라벨 기반 선택 시에만 라벨 검사, 나머지 선택지는 무조건 통과)

  build:
    needs: filter
    # Next.js 등 빌드를 1회만 수행, artifact 업로드

  generate-shards-matrix:
    needs: filter
    # {{PACKAGE_MANAGER}} run test:e2e -- --list 로 총 개수 측정
    # 15개당 1 shard 계산
    # outputs: matrix, shard-count

  e2e-test:
    needs: [build, generate-shards-matrix]
    strategy:
      matrix:
        include: ${{ fromJSON(needs.generate-shards-matrix.outputs.matrix) }}
    steps:
      - actions/download-artifact (빌드 결과)
      - {{PACKAGE_MANAGER}} run test:e2e -- --shard=${{ matrix.shard-index }}/${{ matrix.total-shards }} --reporter=blob

  merge-reports:
    needs: [e2e-test]
    if: ${{ always() && needs.e2e-test.result == 'failure' }}
    steps:
      - playwright merge-reports → HTML
      - actions/upload-artifact (병합된 리포트)
```

### 4.2.4 사용자 보고

```
✅ Dynamic Shard CI 추가 완료

생성:
- .github/workflows/playwright.yml

동작 방식:
- 트리거: <사용자 선택>
- 빌드는 1회 → artifact로 shard들이 공유
- 테스트 개수에 비례해 shard 자동 생성 (15개당 1)
- 실패 시 shard 리포트를 1개 HTML로 병합

다음 단계:
- 첫 실행: PR에 `e2e` 라벨을 붙여 트리거 확인
- 실패 시 Actions 탭에서 병합된 HTML 리포트 다운로드
```

---

## 4.3 알림 추가 (선택)

사용자가 명시적으로 요청할 때만 실행. Slack/Mattermost webhook을 워크플로우 끝에 추가.

```yaml
# .github/workflows/playwright.yml 끝에 추가
- name: Notify
  if: always()
  uses: slackapi/slack-github-action@v1
  with:
    payload: |
      {
        "text": "E2E 결과: ${{ needs.e2e-test.result }}",
        "blocks": [...]
      }
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

Secret 등록 안내:
```
GitHub → Settings → Secrets and variables → Actions
- SLACK_WEBHOOK_URL 추가
```

---

## 통합 보고 (여러 확장 동시 적용 시)

```
✅ Phase 4 완료

추가된 확장:
- VRT: e2e/helpers/vrt.ts, 예시 1개 (CI 게이트 미강제)
- CI: .github/workflows/playwright.yml (Dynamic Shard)
- 알림: Slack webhook 연동 (Secret 등록 필요)

다음 단계:
- VRT 베이스라인 생성: pnpm test:vrt-update
- CI 첫 실행: PR에 e2e 라벨 부여
- Secret 등록: SLACK_WEBHOOK_URL
```
