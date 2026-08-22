# Phase 4 — 확장 절차

VRT(시각적 회귀 테스트)와 티어링 CI를 추가하는 페이즈. **메인 스레드만 사용** (서브에이전트 불필요, 결정론적 템플릿 작업).

사용자 입력 키워드:
- "VRT", "스크린샷 테스트" → 4.1 VRT 추가
- "CI", "워크플로우", "GitHub Actions", "병렬화", "shard", "티어", "라벨" → 4.2 티어링 CI 추가
- "도메인만", "바뀐 것만", "스코프" → 4.4 도메인 스코프 (4.2 이후에만)
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

test('랜딩 페이지', { tag: ['@vrt'] }, async ({ page }) => {
  await page.goto('/');
  await takeVrtSnapshot(page, 'landing', {
    mask: ['[data-dynamic="true"]'],
  });
});
```

`@vrt` 태그가 핵심 — CI의 **모든 티어가 `--grep-invert @vrt` 로 이 태그를 제외**한다.
태그 규약 전체는 `SKILL.md` 의 "테스트 태그 규약" 절이 단일 출처다.

> 제목에 `@vrt` 를 넣는 예전 방식(`test('랜딩 페이지 @vrt', ...)`)도 `--grep` 에 동일하게
> 매칭되므로 기존 프로젝트는 그대로 동작한다. 새로 만드는 것만 `tag` 옵션을 쓴다.

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

## 4.2 티어링 CI 추가

매 PR마다 전체 E2E를 돌리면 러너 비용이 선형으로 는다. 이 절차는 **"무엇이 바뀌었고 어디로
가는 PR인가"에 따라 실행 범위를 나누는** 워크플로우를 생성한다.

### 4.2.0 선행 조건 — config의 CI 서버 기동 확인 (건너뛰지 말 것)

워크플로우는 빌드 산출물만 내려받고 **앱 서버를 직접 띄우지 않는다**. 서버는
`playwright.config.ts` 의 `webServer` 가 띄운다. 따라서 CI를 붙이기 전에 config를 확인한다:

```bash
grep -n "USE_LOCAL_SERVER\|webServer" playwright.config.ts
```

`webServer: process.env.CI ? undefined : {...}` 형태(v0.4.0 이하에서 생성된 config)라면
**CI에서 서버가 뜨지 않아 모든 테스트가 `ERR_CONNECTION_REFUSED` 로 실패한다.**
이 경우 `assets/templates/playwright.config.ts.tmpl` 의 `USE_LOCAL_SERVER` / `webServer` 블록으로
갱신하고, `{{START_CMD}}` 는 `references/phase-1-setup.md` Step 4의 **START_CMD 포트 규칙 표**를
따라 확정한다 (프레임워크 기본 포트를 믿지 말 것 — 그 표가 단일 출처다).

### 4.2.0-b 선행 조건 — pnpm 프로젝트의 `packageManager` 필드

`{{PACKAGE_MANAGER}}` 가 **pnpm** 일 때만 해당한다. 템플릿은 `pnpm/action-setup@v4` 를 `version`
입력 없이 쓰는데, 이 액션은 `version` 입력이나 `package.json` 의 `packageManager` 필드 중 하나를
반드시 요구한다. 둘 다 없으면 `No pnpm version is specified` 로 **build job 첫 스텝부터 실패**하고,
그 결과 E2E Gate 가 빨간불이 되어 모든 PR 이 막힌다.

```bash
node -p "require('./package.json').packageManager ?? '(없음)'"
```

`(없음)` 이면 사용자에게 아래 중 하나를 제안하고 확인을 받는다:

| 선택 | 조치 |
|---|---|
| **권장** — `packageManager` 추가 | `package.json` 에 `"packageManager": "pnpm@<설치된 버전>"` 추가 (`pnpm --version` 으로 확인). corepack 표준이라 로컬·CI 버전이 함께 고정된다 |
| 워크플로우에만 고정 | 3개 job 의 `pnpm/action-setup@v4` 에 `with: { version: <버전> }` 추가 |

yarn·npm 은 이 제약이 없다.

### 4.2.1 사용자 의도 확인

`AskUserQuestion`:

1. **야간 전체 실행(nightly)을 켤지?** → 켜면 `schedule` 유지, 끄면 `on:` 의 `schedule` 블록 2줄 삭제
2. **기본 브랜치명** (`main` / `master` / 기타) — `git symbolic-ref refs/remotes/origin/HEAD` 로 먼저 감지하고 확인만 받는다
3. **빌드/기동 명령** — Phase 1의 Analyzer 결과(`dev_command`, `start_command`)와 `package.json` scripts 교차확인

티어 체계 자체는 선택지가 아니다. 사용자가 "전부 다 돌려줘" 를 원하면 `e2e:full` 라벨 운영을 안내한다.

### 4.2.2 파일 생성

`.github/workflows/playwright.yml` 을 `assets/templates/ci/playwright-e2e.yml.tmpl` 로부터 생성. 치환 변수:

| 플레이스홀더 | 값 |
|---|---|
| `{{PACKAGE_MANAGER}}` | pnpm / npm / yarn. `actions/setup-node` 의 `cache:` 입력과 pnpm 셋업 조건에 쓰인다 |
| `{{PW_EXEC}}` | 로컬 playwright 실행 프리픽스. pnpm → `pnpm exec`, **npm → `npx`**, yarn → `yarn exec`. `{{PACKAGE_MANAGER}} exec` 로 뭉뚱그리지 말 것 (`npm exec` 는 뒤따르는 `--grep`·`--shard` 플래그를 npm 이 소비한다) |
| `{{INSTALL_CMD}}` | `pnpm install --frozen-lockfile` / `npm ci` / `yarn install --frozen-lockfile` |
| `{{BUILD_CMD}}` | `pnpm build` 등 |
| `{{START_CMD}}` | 프로덕션 빌드 기동 명령. **BASE_URL 과 같은 포트에 명시 바인딩** (phase-1-setup.md Step 4 표) |
| `{{NODE_VERSION}}` | `20` (기본) 또는 `.nvmrc` / `engines` 감지값 |
| `{{DEFAULT_BRANCH}}` | `main` 등. `git symbolic-ref refs/remotes/origin/HEAD` 로 감지 |
| `{{NIGHTLY_CRON}}` | `0 22 * * *` (매일 KST 07:00). 4.2.1에서 nightly 를 끄면 schedule 블록째 삭제 |
| `{{SKIP_PATHS_REGEX}}` | E2E 무관 경로 ERE. **기본값은 바로 아래 코드 블록에서 그대로 복사할 것** (표 셀에는 정확한 값을 적을 수 없다 — 아래 설명 참고) |
| `{{PRIMARY_PROJECT}}` | 기본 실행 project 이름. config 의 첫 project (기본 `chromium-desktop`) |

#### `{{SKIP_PATHS_REGEX}}` 기본값

마크다운 표 안에서는 `|` 가 셀 구분자라 `\|` 로 이스케이프해야 하는데, ERE 에서 `\|` 는 교대(alternation)가
아니라 **리터럴 파이프 문자**로 해석된다. 이스케이프된 값을 그대로 치환하면 어떤 파일명과도 매치되지
않아 경로 기반 skip 이 조용히 무력화된다. 반드시 아래 블록의 값을 그대로 쓴다:

```
^(docs/.*|.*\.(md|mdx|txt)|LICENSE|\.editorconfig|\.prettierrc.*)$
```

프로젝트에 맞게 조정할 때도 백슬래시는 `.` 을 리터럴로 만들 때만 쓴다 (`\.md`). `|` 앞에는 절대 붙이지 않는다.

치환 후 아래 두 명령으로 검증한다. `<치환한 regex>` 자리에 실제로 넣은 값을 그대로 붙인다:

```bash
printf '%s\n' docs/a.md README.md LICENSE | grep -vE '<치환한 regex>'
```
→ **출력이 없어야 한다.** 한 줄이라도 나오면 이스케이프가 잘못된 것이다.

```bash
printf '%s\n' src/app/page.tsx README.md | grep -vE '<치환한 regex>'
```
→ **`src/app/page.tsx` 만 남아야 한다.**

> **Bun 프로젝트 주의**: 이 템플릿은 `actions/setup-node` 의 `cache` (npm/yarn/pnpm 만 지원)와
> pnpm 셋업만 다루므로 **bun 을 그대로 지원하지 않는다**. bun 프로젝트는 (1) 각 job 에
> `oven-sh/setup-bun@v2` 스텝을 추가하고, (2) `setup-node` 의 `cache:` 입력을 제거하며,
> (3) `{{PW_EXEC}}` 를 `bunx`, `{{INSTALL_CMD}}` 를 `bun install --frozen-lockfile` 로
> 치환하는 수동 조정이 필요하다. (Phase 1·3 의 로컬 실행 명령은 bun/bunx 를 완전히 지원한다 —
> 이 제약은 CI 워크플로우에 한정된다.)

### 4.2.3 티어 예산

| 티어 | 진입 | 실행 범위 | tests/shard | shard 상한 | project | timeout |
|---|---|---|---|---|---|---|
| `skip` | `e2e:skip` 라벨 / draft PR / 무관 경로만 변경 | 없음 | — | 0 | — | — |
| `smoke` | **PR 기본값** | `--grep @smoke` | (고정) | **1** | `{{PRIMARY_PROJECT}}` | 10분 |
| `scoped` | PR + `e2e/ci-scope.json` 매칭 (4.4) | 매칭 도메인 디렉터리 | 15 | 4 | `{{PRIMARY_PROJECT}}` | 20분 |
| `critical` | 기본 브랜치 push / `merge_group` | `--grep "@smoke\|@critical"` | 20 | 4 | `{{PRIMARY_PROJECT}}` | 20분 |
| `full` | `e2e:full` 라벨 | 전체 | 15 | 8 | `{{PRIMARY_PROJECT}}` | 30분 |
| `nightly` | `schedule` | 전체 | **40** | **3** | config 전체 | 60분 |

모든 티어가 `--grep-invert @vrt` 로 VRT를 제외한다.

설계 근거 (사용자가 파라미터를 바꾸려 할 때 설명할 것):
- **smoke는 shard 1 고정.** 테스트 몇 개를 2 shard로 쪼개면 job 오버헤드(checkout+install ≈ 60초)가
  실행 시간보다 크다. shard는 wall-clock을 줄이지만 job마다 오버헤드를 복제한다.
- **nightly는 밀도 40 / 상한 3.** 시간 제약이 없으니 job 수를 최소화해 비용을 줄인다 —
  smoke/full과 **정반대 방향**의 최적화다.
- **nightly만 `--project` 미지정** → config의 모든 project 실행. 사용자가 `chromium-mobile`
  주석을 해제하면 야간에만 자동 포함된다.
- **timeout은 티어별 상한.** 미지정 시 GitHub 기본은 360분이라 서버 hang 한 번이 6시간 과금이다.

### 4.2.4 티어 결정 순서 (위→아래 첫 매치)

| # | 조건 | tier |
|---|---|---|
| 1 | `workflow_dispatch` + `inputs.tier` | 지정값 |
| 2 | `e2e:skip` 라벨 보유 | `skip` |
| 3 | `e2e:full` 라벨 보유 | `full` |
| 4 | draft PR | `skip` |
| 5 | 변경 파일이 전부 `{{SKIP_PATHS_REGEX}}` 매치 (**파일 0개면 관련 있음**) | `skip` |
| 6 | `schedule` | `nightly` |
| 7 | `push`(기본 브랜치) / `merge_group` | `critical` |
| 8 | 그 외 PR → `ci-scope.json` 없으면 `smoke`, 있으면 4.4 | `smoke`/`scoped`/`full` |

**명시적 라벨(2·3행)이 암묵 판정(4·5행)보다 위**에 온다. 라벨은 사용자의 의사표시이므로
draft나 경로 휴리스틱이 뒤집지 않는다.

수정 시 반드시 지킬 것:
- **라벨 판정은 `github.event.pull_request.labels.*.name` (현재 상태)** 으로 한다.
  `github.event.label` (이벤트 순간값)을 쓰면 라벨을 붙인 그 순간 1회만 돌고
  이후 push(`synchronize`)에는 돌지 않는다.
- **라벨 비교는 `,` 로 감싼 정확 일치.** 부분 문자열 매치는 `e2e:full-stack` 을 `e2e:full` 로 오인한다.
- **라벨명·파일명은 사용자 제어 입력.** `run:` 블록에 `${{ }}` 로 직접 보간하면 스크립트
  인젝션이 되므로 반드시 `env:` 를 경유한다.
- **`gh api` 실패 시 `relevant=true` 폴백 + `::warning::`.** 경고가 없으면 경로 skip 기능이
  조용히 무력화된 채로 동작한다.

### 4.2.5 조용한 무실행 방지 (안전장치 — 절대 생략 금지)

태그를 아직 안 붙인 프로젝트에서 `--grep @smoke` 가 0개를 매칭하면 "아무것도 안 돌았는데
초록불"이 된다. 이게 이 워크플로우의 최악 실패 모드다.

**Playwright 동작의 비대칭**:
- `playwright test --list --grep X` 는 매칭이 0개면 `No tests found` 로 **exit 1** 이다.
  개수 측정 스텝에는 **`--pass-with-no-tests`** 를 붙여야 0이 정상 출력된다.
- 실행 스텝은 `--shard` 가 있으면 0개여도 exit 0 이 되는 버전이 있다. 이 버전 의존성에
  기대지 말고 **실행 스텝에도 `--pass-with-no-tests` 를 붙여 동작을 고정**하고,
  통과/실패 판정은 오직 `build.outputs.total` 과 gate로만 한다.
- **개수 측정과 실행은 동일한 `--grep`/경로/`--project` 인자를 써야 한다.** 인자가 갈라지면
  "5개 세고 0개 실행"이 조용히 통과한다.

규칙:
- `smoke`/`scoped`/`critical` 에서 총계 0 → **`full` 로 승격** + `::warning::` + job summary 기록 후 재측정
- 승격 후에도 0 → `total=0` 출력 → `e2e-test` 는 skip → gate는 green + `::warning::`
- Phase 1이 생성하는 예시 spec에 `@smoke` 가 붙어 있어 최소 1개는 보장된다

### 4.2.6 E2E Gate (branch protection)

shard 개수가 동적이라 개별 job 이름을 required check로 등록할 수 없다. 항상 도는 단일
gate job이 그 역할을 한다.

| decide | tier | build | total | e2e-test | gate |
|---|---|---|---|---|---|
| ≠ success | — | — | — | — | **실패** |
| success | `skip` | skipped | — | skipped | 성공 + notice |
| success | ≠ skip | ≠ success | — | skipped | **실패** |
| success | ≠ skip | success | `0` | skipped | 성공 + warning |
| success | ≠ skip | success | >0 | success | 성공 |
| success | ≠ skip | success | >0 | 그 외 | **실패** |

**"skipped = 성공" 은 tier=skip 또는 total=0 일 때만 허용**된다. 그 밖의 skipped 는 전부 상위
job 실패의 결과이므로 실패다 (build가 깨졌는데 gate가 green이면 결함을 그대로 머지하게 된다).

`on.pull_request.paths:` 로 걸러내지 않는 이유: 그러면 워크플로우 자체가 트리거되지 않아
required check가 영원히 pending으로 남는다. job-level `if:` 로 skip해야 skipped가 성공으로
집계된다 — 그래서 경로 필터를 `on:` 이 아니라 decide job 안에 둔다.

### 4.2.7 사용자에게 안내할 후속 설정

워크플로우 파일만으로는 끝나지 않는다. 다음 3가지를 **명령/경로와 함께** 안내한다:

1. **라벨 2개 생성**
   ```bash
   gh label create "e2e:full" --description "이 PR 에서 E2E 전체 스위트 실행" --color 0E8A16
   gh label create "e2e:skip" --description "이 PR 에서 E2E 건너뛰기" --color C5DEF5
   ```
2. **branch protection에 `E2E Gate` 만 required check로 등록**
   (Settings → Branches → 대상 브랜치 → Require status checks → `E2E Gate`)
3. **`@smoke` / `@critical` 태그 부여** — 태그가 없으면 매 PR이 full로 승격되어 비용 절감이 없다.
   Phase 2가 신규 spec에 자동 부여하지만, 기존 spec은 사용자가 붙여야 한다.

### 4.2.8 사용자 보고

```
✅ 티어링 CI 추가 완료

생성:
- .github/workflows/playwright.yml

실행 티어:
- PR 기본        → @smoke 만 (shard 1, ~3분)
- e2e:full 라벨  → 전체 스위트 (shard 최대 8)
- e2e:skip 라벨  → 건너뛰기
- main 반영      → @smoke|@critical
- 야간 스케줄    → 전체 + config 의 모든 project
- 문서/마크다운만 변경한 PR, draft PR → 자동 skip

필요한 후속 설정 (3가지):
1. 라벨 생성: gh label create "e2e:full" ... / "e2e:skip" ...
2. branch protection 의 required check 에 "E2E Gate" 등록
3. 기존 spec 에 @smoke / @critical 태그 부여
   (태그가 하나도 없으면 매 PR 이 전체 스위트로 승격됩니다)

첫 실행 확인:
- PR 을 열면 smoke 티어가 돕니다
- e2e:full 라벨을 붙이면 전체로 전환되고, 그 라벨을 유지한 채 커밋을 더 밀어도 계속 전체가 돕니다
- 실패 시 Actions 탭에서 e2e-html-report 아티팩트 다운로드
```

---

## 4.3 알림 추가 (선택)

사용자가 명시적으로 요청할 때만 실행. Slack/Mattermost webhook을 `e2e-gate` job 끝에 추가한다
(gate가 최종 판정을 아는 유일한 job이다).

```yaml
      - name: Notify
        if: ${{ !cancelled() }}
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "E2E ${{ needs.e2e-test.result }} (tier=${{ needs.decide.outputs.tier }})"
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

Secret 등록 안내:
```
GitHub → Settings → Secrets and variables → Actions
- SLACK_WEBHOOK_URL 추가
```

> `skip` 티어에서도 알림이 가면 소음이 된다. 필요하면
> `if: ${{ !cancelled() && needs.decide.outputs.tier != 'skip' }}` 로 좁힌다.

---

## 4.4 도메인 스코프 실행 (선택 기능)

4.2를 이미 적용한 프로젝트에서 "바뀐 영역만 돌려줘" 요청이 올 때 실행한다.

### 4.4.1 동작

`e2e/ci-scope.json` **파일이 존재할 때만** 켜진다. 이 스킬의 `e2e/tests/{도메인}/` 구조와
1:1로 매핑된다.

스코프는 **PR 기본 티어(smoke)를 넓히는** 기능이다. `e2e:full` 은 명시 의사이므로 절대 좁히지
않는다 ("전부 돌려" 라벨을 붙였는데 2개 도메인만 돌면 배신이다).

결정 순서 8행에서:

| 상황 | 결과 |
|---|---|
| `always` 경로가 하나라도 변경됨 | `full` (스코핑 미적용) |
| 매칭 도메인 ≥ 1 | `scoped` — `playwright test e2e/tests/{도메인} ...` |
| 매칭 도메인 0 | `fallback` 값 (`full` \| `smoke`) |

전부 "의심스러우면 넓게" 방향이다. 도메인명은 경로 인자로 쉘에 전달되므로 `[A-Za-z0-9._-]`
문자셋만 허용하고, 벗어나면 무시 + 경고한다.

### 4.4.2 파일 생성

`assets/templates/ci/ci-scope.example.json.tmpl` 을 `e2e/ci-scope.json` 으로 복사한 뒤,
**사용자 프로젝트의 실제 경로로 도메인 매핑을 다시 쓴다** (예시 값을 그대로 두면 안 된다).

매핑 작성 절차:
1. `e2e/tests/` 의 도메인 디렉터리 목록을 Glob으로 수집
2. 각 도메인에 대응하는 소스 경로를 사용자에게 확인 (`AskUserQuestion` 또는 라우팅 구조에서 추론 후 제시)
3. 공용 컴포넌트·설정·Helper 경로를 `always` 에 넣는다

### 4.4.3 fallback 값 선택

**매핑이 성숙하기 전에는 `"fallback": "smoke"` 를 권장한다.** `full` 로 두면 매핑에 걸리지 않는
PR이 전부 전체 스위트를 돌려 이 기능이 오히려 비용을 늘린다. 매핑이 안정되면 `full` 로 올린다.

### 4.4.4 사용자 보고

```
✅ 도메인 스코프 실행 활성화

생성:
- e2e/ci-scope.json (도메인 N개 매핑)

동작:
- PR 에서 변경 경로 → 영향 도메인만 실행 (scoped 티어)
- 공용 경로(always) 변경 시 → 전체
- 매칭 도메인 없음 → fallback = <값>
- e2e:full 라벨은 이 매핑을 무시하고 항상 전체

⚠️ 매핑이 틀리면 "테스트가 조용히 안 도는" 실패 모드가 됩니다.
   앱 구조를 바꿀 때 ci-scope.json 도 함께 갱신하세요.
```

---

## 통합 보고 (여러 확장 동시 적용 시)

```
✅ Phase 4 완료

추가된 확장:
- VRT: e2e/helpers/vrt.ts, 예시 1개 (CI 게이트 미강제)
- CI: .github/workflows/playwright.yml (티어링)
- 스코프: e2e/ci-scope.json
- 알림: Slack webhook 연동 (Secret 등록 필요)

다음 단계:
- VRT 베이스라인 생성: pnpm test:vrt-update
- 라벨 생성 + branch protection 에 "E2E Gate" 등록
- 기존 spec 에 @smoke / @critical 부여
- Secret 등록: SLACK_WEBHOOK_URL
```
