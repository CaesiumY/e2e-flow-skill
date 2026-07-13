# Phase 3 — 자가 복구 루프 절차

테스트 실행 → (컴파일 에러 사전 필터) → 실패 분석 → 4분류 → edits 적용 → 재실행 루프. **spec별 최대 3회 실행**(edits 적용은 최대 2회)하고 그래도 실패하면 최종 보고. 분석·분류는 **Self-Healer 서브에이전트**(`model: sonnet`)가 담당하고, 실행·검증·edits 적용·재실행은 메인 스레드가 오케스트레이션한다.

**시도 정의 (A4)**: 시도 = 대상 spec 파일 실행 1회. **최초 실행이 시도 1.** spec별 **최대 3회 실행**하고, 그 사이 **edits 적용은 최대 2회**다 — 시도 3의 제안 edits는 적용하지 않고 최종 보고에 첨부한다. 카운터는 **spec 파일별 독립**으로 센다. 같은 spec 안의 복수 `test()` 실패는 한 번의 Self-Healer 디스패치로 묶어 전달한다(`{{TEST_NAME}}`에 나열). 병렬 디스패치는 **서로 다른 spec에만** 허용한다.

---

## 루프 구조

```
[메인] Step 0: 대상 spec 확정 + 패키지 매니저 감지 (미확정 시)
   ↓
[메인] Step 1: 대상 테스트 실행 (이 실행이 시도 N, timeout 600000ms)
   ↓ 통과? → Step 2 성공 보고, 종료
   ↓ 실패
[메인] Step 1.5: 컴파일 에러 사전 필터
   ├─ TS####/SyntaxError/Cannot find module → 메인이 직접 수정 후 Step 1 재실행
   │                                            (Self-Healer 디스패치 안 함)
   └─ 정적 결함 신호 없음 → 아래로
   ↓
[메인] Step 3: trace/screenshot/에러 로그 수집 → 형식 토큰 채우기
   ↓
[서브: Self-Healer / model: sonnet] Step 4: 분석 → 4분류 → edits 제안
   ↓
[메인] Step 4.5: 응답 형식 검증 (위반 시 1회 재디스패치 → 재실패면 사용자 보고)
   ↓
[메인] Step 5.0: 재검 게이트 3종 (하나라도 실패 → 자동 적용 차단, 사용자 검토)
   ↓
[메인] Step 5: classification 분기
   ├─ UI_CHANGE / TEST_BUG (confidence ≥ 0.5, 게이트 통과)
   │    → Step 6: 시도 3이면 적용 없이 Step 7(제안 edits 첨부) / 3 미만이면 edits 적용 후 Step 1 재실행
   ├─ UI_CHANGE / TEST_BUG (confidence < 0.5 또는 게이트 차단)
   │    → 사용자에게 edits 검토 요청 (자동 적용 안 함)
   └─ APP_BUG / ENV_ISSUE
        → 절대 수정 안 함, 즉시 보고하고 루프 종료
   ↓
시도 3의 실행까지 실패? → Step 7 최종 보고하고 종료
```

---

## Step 0. 대상 spec 확정 + 패키지 매니저 감지

### 0.1 대상 spec 확정

Phase 2에서 연계 진입한 경우 대상은 **방금 생성한 `{시나리오}.spec.ts`**로 이미 확정돼 있다(`references/phase-2-generate.md` Step 5). **"테스트 깨졌어 / 고쳐줘" 키워드 + 실패 출력 첨부로 Phase 3에 직접 진입한 경로**는 대상이 지정돼 있지 않으므로, 아래 순서로 확정한다:

1. **실패 출력 파싱**: 사용자가 붙여넣은 Playwright 출력에서 실패 spec의 파일 경로(`e2e/**/*.spec.ts` 패턴, 리포터 라인의 파일 경로)를 추출한다. 두 건 이상이면 **다중 실패 정책**(본 문서 하단)을 따라 spec 파일 단위로 그룹화한다.
2. **파싱 실패 시**: 출력에 파일 경로가 없으면 `AskUserQuestion`으로 대상 spec 경로를 확인한다.
3. **사용자도 특정 못 하면**: 전체 스위트를 1회 실행해 실패 spec 목록을 수집한다. **이 전체 실행은 수집된 각 실패 spec의 시도 1로 계산**한다(같은 spec을 곧바로 다시 실행하지 않는다).

### 0.2 패키지 매니저 감지

Phase 2에서 연계 진입한 경우 Phase 1/Analyzer가 감지한 값을 그대로 사용한다. 직접 진입한 경로는 감지된 값이 없으므로, 실행 전 반드시 아래 규칙(A7)으로 확정한다.

| 신호 (우선순위 순) | 결과 |
|---|---|
| `pnpm-lock.yaml` 존재 | pnpm |
| `yarn.lock` 존재 | yarn |
| `package-lock.json` 존재 | npm |
| `bun.lockb` 존재 | bun |
| lockfile 없음 → `package.json`의 `packageManager` 필드 | 해당 매니저 |
| 그래도 없음 | `npx` 폴백 |

확정된 매니저에 따라 **Step 1의 실행 명령을 하나만** 고른다.

| 매니저 | 실행 명령 |
|---|---|
| pnpm | `pnpm exec playwright test ...` |
| yarn | `yarn playwright test ...` |
| npm | `npx playwright test ...` |
| bun | `bunx playwright test ...` |

---

## Step 1. 테스트 실행

대상 테스트만 실행한다 (전체가 아닌). Step 0에서 확정한 매니저 명령을 사용한다.

```bash
# 감지 결과에 따라 아래 중 하나만 사용
pnpm exec playwright test {대상 spec 경로} --reporter=list --trace=on
```

`--trace=on`을 강제로 활성화 (자가 복구의 입력으로 필수).

**Bash 실행 시 주의**:
- **timeout: `600000`ms (10분, 도구 최대값)** 로 지정한다. E2E는 3~5분도 정상이므로 기본값(120000ms)으로는 정상 테스트가 잘려 오분류된다.
- 타임아웃으로 잘린 출력은 **실패로 분류하지 말고**, 대상 spec을 축소하거나 단일 테스트를 지정한 뒤 재실행한다.
- **webServer 인지**: `playwright.config`에 `webServer`가 있으면 dev 서버 자동 기동을 신뢰한다. 없으면(CI 등) 대상 앱이 기동/빌드됐는지 먼저 확인한다.
- stdout/stderr 둘 다 캡처.
- exit code 확인 (0: 통과, 비제로: 실패).

이 실행 1회가 **시도 1회**다 (최초 실행 = 시도 1).

---

## Step 1.5. 컴파일 에러 사전 필터

실행 출력에 **TS 컴파일 에러(`TS####`), `SyntaxError`, `Cannot find module` 등 정적 결함 신호**가 있으면 이는 4분류 대상이 **아니다**. Self-Healer를 디스패치하지 않고, **메인 스레드가 import 경로·시그니처를 직접 수정**한 뒤 Step 1로 돌아가 재실행한다.

- 이 재실행도 **시도 횟수에 포함**된다 (실행 1회 = 시도 1회).
- 정적 결함 신호가 없으면 Step 3으로 진행한다.

> 이 규칙은 `references/failure-classification.md`의 "분류 대상 전제"와 동일 문구다 — 두 문서가 같은 계약을 공유한다.

---

## Step 2. 통과 처리

exit code 0이면:

```
✅ Phase 3 완료: 테스트 통과
  - 대상: e2e/tests/agent/specs/create.spec.ts
  - 실행 시간: 12.4초
  - 시도 횟수: 1   # 최초 실행에서 통과 = 시도 1

다음 단계 안내:
- 추가 시나리오 생성: 자연어로 요청
- VRT 추가: "VRT 붙여줘"
- CI 추가: "E2E CI 워크플로우 추가해줘"
```

루프 종료.

---

## Step 3. 실패 시 컨텍스트 수집

Self-Healer 프롬프트(`assets/prompts/self-healer.md`)의 형식 토큰을 채울 값을 수집한다. **프롬프트 본문의 규칙(Selector 우선순위·4분류·자연어 매핑)은 이미 프롬프트에 내장되어 있으므로, 여기서는 실패별 데이터만 채운다.**

| 형식 토큰 | 채울 값 | 수집 방법 |
|---|---|---|
| `{{SPEC_PATH}}` / `{{TEST_NAME}}` | 실패한 spec 경로·테스트 이름 | Bash 출력 |
| `{{SPEC_CONTENT}}` | 실패한 spec 파일 전체 내용 | Read |
| `{{FLOW_CONTENT}}` | 참조 flow 파일 (있는 경우) | Read |
| `{{HELPER_CONTENT}}` | 참조 Helper 파일 (selector 실패면 필수) | Read |
| `{{HELPER_SIGNATURES}}` | **프로젝트 실제 `e2e/helpers/*.ts`의 클래스·메서드 시그니처** | Grep |
| `{{PLAYWRIGHT_ERROR}}` | Playwright 에러 메시지 전문 | Bash 출력에서 추출 |
| `{{TRACE_REF}}` | trace/screenshot 경로 | `test-results/.../trace.zip`, `playwright-report/data/*.png` |
| `{{ATTEMPT}}` | 현재 시도 횟수 / 최대 3 | 메인이 카운트 |
| `{{PRIOR_ATTEMPTS}}` | 시도별 `{classification, edits 요약, 결과(해결/미해결)}` | 메인이 보관한 이력 |

**{{HELPER_SIGNATURES}} 주의**: 스킬 템플릿(`references/helper-templates.md`)이 아니라 **현재 프로젝트의 실제 `e2e/helpers/*.ts`에서 Grep으로 추출**한다. 자가 복구가 이전 시도에 Helper를 수정했다면 템플릿과 실제 코드가 다르기 때문이다. 예:

```bash
# 클래스·public 메서드 시그니처만 추출
grep -nE "class |async |^\s+[a-zA-Z]+\(" e2e/helpers/*.ts
```

**{{TRACE_REF}} 주의**: 스크린샷은 Read 도구가 이미지를 받을 수 있으므로 **Healer에게 image input으로 전달**한다. 가능하면 trace를 풀어 핵심 screenshot 경로를 확보하고, 못 하면 trace 디렉터리 경로와 핵심 파일 목록을 텍스트로 전달한다.

**{{PRIOR_ATTEMPTS}} 주의**: 2·3회차 디스패치에서는 반드시 이전 시도의 `{classification, 적용한 edits 요약, 결과}`를 채운다. 비우면 Healer가 이미 실패한 같은 가설을 재제안해 시도 예산만 소진한다.

---

## Step 4. Self-Healer 디스패치

`assets/prompts/self-healer.md`의 프롬프트 본문에서 Step 3의 형식 토큰을 치환해 `general-purpose` 서브에이전트를 **`model: sonnet`으로** 호출한다.

```text
Agent({
  description: "Analyze Playwright test failure and propose edits",
  subagent_type: "general-purpose",
  model: "sonnet",
  prompt: <self-healer.md 본문에서 {{...}} 토큰을 Step 3 값으로 치환한 문자열>
})
```

**전달 원칙 (단일 출처)**:
- self-healer.md에 **Selector 우선순위·4분류 매트릭스·자연어→코드 매핑의 축약본이 이미 내장**되어 있다. 이것이 단일 출처다.
- `references/selector-priority.md`·`references/failure-classification.md`의 **전문을 재임베드하지 않는다** — 중복·모순·컨텍스트 낭비만 낳는다.
- 메인이 하는 일은 오직 **형식 토큰 채우기**뿐이다.

**폴백 (A2)**: `model` 파라미터를 지원하지 않는 호스트에서는 `model` 인자를 생략한다 (메인 모델 상속). 동작은 동일하고 비용만 증가한다.

---

## Step 4.5. 응답 형식 검증

Healer 응답(YAML 헤더 + EDIT 블록)이 계약을 지켰는지 메인이 먼저 검증한다:

- (a) **YAML 헤더 파싱 가능** (classification / confidence / reasoning / edits_count / notes_to_user)
- (b) **classification이 4값 중 하나** (UI_CHANGE / TEST_BUG / APP_BUG / ENV_ISSUE)
- (c) **confidence가 0.0~1.0 숫자**
- (d) **edits_count와 실제 EDIT 블록 수 일치**
- (e) **APP_BUG / ENV_ISSUE면 edits_count가 0** (EDIT 블록 없음)

**위반 시**: "지정 형식만 출력하라"를 덧붙여 **동일 프롬프트로 1회 재디스패치**한다. 재차 위반하면 자동 처리하지 않고, Healer 원문을 첨부해 사용자에게 수동 처리를 요청한다.

---

## Step 5.0. 재검 게이트 (오케스트레이터)

Sonnet 초안을 자동 적용하기 전, 하위 모델 특유의 실패를 메인이 걸러낸다. **아래 3종 중 하나라도 실패하면 자동 적용을 차단하고 사용자 검토로 전환한다.**

1. **근거-신호 정합성**: `reasoning`이 인용한 핵심 에러 신호가 Step 3에서 수집한 **실제 Playwright 출력에 존재**하는지 Grep으로 대조한다. 출력에 없는 신호를 인용했다면 **환각 의심** → 차단.
2. **edits 안전 범위**: 분류가 UI_CHANGE / TEST_BUG인데 edits가 **단언값(`toBe`/`toContain`)** 이나 **`e2e/mocks/`·fixture 파일**을 건드리면 **APP_BUG 의심** → 차단.
3. **confidence 캘리브레이션**: UI_CHANGE인데 **trace/스크린샷 근거 없이 텍스트 에러만**으로 판단했으면 confidence를 **< 0.5로 취급**한다 (자동 적용 차단).

게이트를 모두 통과한 경우에만 Step 5의 자동 적용 분기로 넘어간다.

---

## Step 5. 분기 처리

Healer 응답의 YAML 헤더 구조:

```yaml
classification: UI_CHANGE | TEST_BUG | APP_BUG | ENV_ISSUE
confidence: 0.0 ~ 1.0
reasoning: |
  <2-3문장 분류 근거>
edits_count: 0   # 뒤따르는 EDIT 블록 개수. APP_BUG/ENV_ISSUE는 반드시 0
notes_to_user: |
  <보고용 메시지 / 변경 요약>
```

(edits는 YAML 뒤에 `edits_count` 개수만큼의 EDIT 펜스 블록으로 이어진다.)

### 분기

**UI_CHANGE 또는 TEST_BUG**:
- `confidence ≥ 0.5` **이고 Step 5.0 게이트 통과** → Step 6에서 edits 적용 후 재실행
- `confidence < 0.5` **또는 게이트 차단** → 사용자에게 edits와 reasoning을 보여주고 `AskUserQuestion`으로 적용 여부 확인 (자동 적용 안 함)

**APP_BUG**:
- 즉시 루프 종료
- 다음 보고:
  ```
  🚨 APP_BUG 감지 — 자동 수정하지 않습니다

  분류 근거: <reasoning>
  의심 위치: <notes_to_user>
  trace: <경로>

  앱 코드를 확인하시거나, 의도된 동작이라면 테스트 단언을 수정해주세요.
  ```

**ENV_ISSUE**:
- 즉시 루프 종료
- 다음 보고:
  ```
  ⚠️ ENV_ISSUE 감지 — 자동 수정하지 않습니다

  의심 원인: <reasoning>
  확인 항목:
  - [ ] 개발 서버 기동 여부 (config에 webServer 없으면 직접 기동)
  - [ ] .env 환경변수
  - [ ] mock 핸들러 등록 여부

  환경 보정 후 Step 0의 매니저별 실행 명령 표(위 Step 0.2 참조)에서
  확정한 명령을 그대로 사용해 재시도.
  ```

---

## Step 6. edits 적용

**하드 가드 (시도 3 차단 — 적용 전 먼저 확인)**: 현재 시도 횟수가 **이미 3**이면(=3번째 실행의 실패를 분석한 응답이면) 이 Healer 응답의 edits를 **적용하지 않는다.** 아래 적용 절차를 건너뛰고 곧바로 Step 7 최종 보고로 이동하며, Healer가 제안한 EDIT 블록은 **적용하지 않은 채 보고에 첨부**한다(사용자가 직접 검토·적용). 이렇게 해야 "edits 적용 최대 2회" 불변식(A4)과 self-healer.md의 3회 한도 계약이 지켜지고, 검증되지 않은 3번째 패치가 워킹트리에 남지 않는다.

**시도가 3 미만인 경우에만** 아래 적용을 진행한다. Healer가 반환한 각 EDIT 블록을 메인이 순차 적용한다. **Healer는 파일을 직접 고치지 않으므로, 적용은 전적으로 메인의 책임이다.**

각 EDIT 블록(`file` / `--- OLD ---` / `--- NEW ---`)에 대해:

1. **동일 edits 반복 가드**: 제안된 edit이 `{{PRIOR_ATTEMPTS}}`에서 이미 적용한 것과 동일하면 **적용하지 않는다.** "다른 가설 필요"를 명시해 1회 재디스패치하고, 그래도 동일하면 사용자에게 보고한다.
2. **OLD 유일성 확인**: `file`을 Read해 OLD 텍스트가 파일 내에 **정확히 1회** 존재하는지 확인한다.
3. **적용**: `Edit` 도구로 `old_string`=OLD, `new_string`=NEW 치환.
4. **불일치·중복 시**: OLD가 없거나(0회) 중복 매칭(2회 이상)이면 해당 edit을 **건너뛰고** 사용자에게 보고한다 (형식 오류).

**적용 후**: Step 1로 돌아가 재실행한다 (그 재실행이 다음 시도). 재실행이 다시 실패하고 그것이 시도 3이면, 위 하드 가드에 따라 Step 6에서 적용 없이 Step 7로 간다.

---

## Step 7. 시도 소진 (3회 실행)

시도 3의 실행까지 실패하면 루프 종료. **최종 보고 전에 누적 분류 수렴 여부를 판정한다** — 보관한 시도 이력의 classification이 **TEST_BUG로 수렴**(모두 또는 대부분 TEST_BUG)하고 마지막 Healer 가설이 **flow 구조 자체의 문제**를 지목하면, 아래 "다음 시도 옵션"에 **"Phase 2 재생성"을 함께 제시**한다.

최종 보고:

```
❌ Phase 3 종료: 3회 실행 후에도 실패

대상: e2e/tests/agent/specs/create.spec.ts

시도 이력 (실행 기준):
1. UI_CHANGE (conf 0.7) → edits 적용 (FormHelper.submit label)
2. TEST_BUG (conf 0.6) → edits 적용 (대기 추가)
3. TEST_BUG (conf 0.7) → 시도 3, 하드 가드로 미적용 (제안 edits 아래 첨부)

최종 trace: test-results/.../trace.zip
마지막 가설: <Healer의 마지막 reasoning>

제안 edits (시도 3, 미적용):
<시도 3 Healer의 EDIT 블록 원문 — 사용자가 직접 검토·적용>

다음 시도 옵션:
- 마지막 edits 직접 검토 및 적용
- 앱 코드 확인 (APP_BUG 의심 시)
- 환경 점검 (ENV_ISSUE 의심 시)
- 새 자연어 시나리오로 재시도
- Phase 2 재생성 — 누적 분류가 TEST_BUG로 수렴하고 마지막 가설이 flow 구조 문제를
  가리키는 경우 권장. 선택 시 references/phase-2-generate.md의
  "Phase 3 복귀 진입 (재생성 계약)" 절차로 원본 시나리오·시도 이력·마지막 가설을
  넘겨 재진입한다 (실패한 flow 접근은 명시적으로 배제).
```

**시도 3 = 실행 3회, edits 적용 2회.** 위 예시는 실행 3회를 보여주며, 3번째 실행의 제안 edits는 (confidence·분류와 무관하게) 적용하지 않고 위 "제안 edits (시도 3, 미적용)"에 첨부한다.

---

## 다중 실패 정책 (실패 spec 2개 이상 또는 한 spec에 여러 test() 실패)

Phase 2가 한 spec에 여러 `test()`를 생성했거나 기존 스위트 치유를 요청받으면 여러 테스트가 동시에 실패한다. 이때:

- **(a) spec 단위로 그룹화**: 실패를 **spec 파일 단위**로 묶는다. 실행·토큰 수집·시도 카운트의 기본 단위는 개별 `test()`가 아니라 **spec 파일**이다.
- **(b) 카운터 독립 (A4)**: 시도 카운터와 3회 한도는 **spec 파일별로 독립**이다. 한 spec에 3회를 다 써도 다른 spec의 카운터는 그대로다.
- **(c) 같은 spec 내 복수 test() 실패 = 단일 디스패치**: 한 spec에서 여러 `test()`가 실패하면 **하나의 Self-Healer 디스패치로 묶어** 전달한다. `{{TEST_NAME}}`에 실패한 테스트 이름을 모두 나열하고, `{{PLAYWRIGHT_ERROR}}`는 리포터 출력을 **테스트 이름 경계로 분할해 실패별로 구분**해 채운다. spec 실행은 spec 파일 전체를 한 번에 돌리므로(개별 `test()`를 `-g`로 격리 실행하지 않음) 카운터의 spec 독립성이 자연히 유지된다.
- **(d) 병렬 디스패치는 서로 다른 spec에만**: **서로 다른 spec이고 참조 파일(flow/Helper/mock)이 겹치지 않는** 독립 실패에 한해 Self-Healer를 병렬 디스패치할 수 있다 (**최대 3개 동시**). 같은 spec의 복수 실패는 (c)에 따라 단일 디스패치이므로 병렬 대상이 아니며, 서로 다른 spec이라도 참조 파일이 겹칠 가능성이 있으면 (e) 순차 적용으로 강제한다.
- **(e) 순차 적용 + 충돌 가드**: edits 적용은 **메인이 순차 수행**한다. 여러 edits가 **같은 파일**을 건드려 충돌하면, **첫 패치만 적용**한 뒤 전체를 재실행해 나머지를 재평가한다 (겹친 수정을 무턱대고 병합하지 않는다).

---

## 안전 가드

- **APP_BUG / ENV_ISSUE는 절대 자동 수정하지 않는다** — 분류가 그렇게 나오면 무조건 보고만.
- **컴파일/타입/import 에러는 Self-Healer가 아니라 메인이 직접 처리한다** (Step 1.5).
- **재검 게이트(Step 5.0)를 통과하지 못한 edits는 자동 적용하지 않는다** — 사용자 검토로 전환.
- **단언 값(`toBe(...)`, `toContain(...)`)·mock 응답 데이터를 함부로 바꾸지 않는다** — 보통 APP_BUG의 신호. 게이트에서 차단한다.
- **spec별 3회 실행 한도는 절대 넘기지 않는다** — 무한 루프 방지.

---

## 보고서 메모

각 시도의 `{classification, 적용한 edits 요약, 결과(해결/미해결)}`를 메인 스레드에서 보관한다. 이 이력은 (1) 다음 회차 Healer의 `{{PRIOR_ATTEMPTS}}` 입력으로 **주입**되고, (2) Step 7 최종 보고에 포함된다. 이를 통해 Healer는 실패한 가설을 반복하지 않고, 사용자는 "어떤 가설로 어떻게 수정했는지" 추적할 수 있다.
