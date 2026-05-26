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

- `{{PACKAGE_MANAGER}}` — pnpm/npm/yarn
- `{{INSTALL_CMD}}` — `pnpm install --frozen-lockfile` / `npm ci` / `yarn install --frozen-lockfile`
- `{{BUILD_CMD}}` — `pnpm build` 등
- `{{NODE_VERSION}}` — `20` (기본) 또는 감지값
- `{{TRIGGER_BLOCK}}` — 사용자 선택에 따라 (PR labeled / push / schedule)

### 4.2.3 워크플로우 구조 (요약)

```yaml
name: E2E Tests

on:
  pull_request:
    types: [labeled]   # e2e/release 라벨 시 실행
  workflow_dispatch:   # 수동 실행
  schedule:
    - cron: '0 22 * * *'   # KST 오전 7시

jobs:
  build:
    # Next.js 등 빌드를 1회만 수행, artifact 업로드

  count-tests:
    # pnpm test:e2e --list 로 총 개수 측정
    # 15개당 1 shard 계산
    # JSON matrix 출력

  e2e-test:
    needs: [build, count-tests]
    strategy:
      matrix:
        include: ${{ fromJSON(needs.count-tests.outputs.matrix) }}
    steps:
      - actions/download-artifact (빌드 결과)
      - pnpm exec playwright test --shard=${{ matrix.shard-index }}/${{ matrix.total-shards }} --reporter=blob

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
