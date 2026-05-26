# Phase 3 — 자가 복구 루프 절차

테스트 실행 → 실패 분석 → 분류 → 패치 적용 → 재실행 루프. **최대 3회** 반복하고 그래도 실패하면 최종 보고. 분석·분류는 **Self-Healer 서브에이전트**가 담당하고, 실행·패치 적용·재실행은 메인 스레드가 오케스트레이션한다.

---

## 루프 구조

```
[메인] 대상 테스트 실행
   ↓ 통과? 종료 (성공 보고)
   ↓ 실패
[메인] trace/screenshot/에러 로그 수집
   ↓
[서브: Self-Healer] 분석 → 4분류 → 패치 제안
   ↓
[메인] classification 검토:
   ├─ UI_CHANGE / TEST_BUG (confidence ≥ 0.5)
   │    → 패치 적용 → 1단계로 (시도 횟수 +1)
   │
   ├─ UI_CHANGE / TEST_BUG (confidence < 0.5)
   │    → 사용자에게 패치 검토 요청 (자동 적용 안 함)
   │
   └─ APP_BUG / ENV_ISSUE
        → 절대 수정 안 함, 즉시 보고하고 루프 종료
   ↓
시도 횟수 ≥ 3? → 최종 보고하고 종료
```

---

## Step 1. 테스트 실행

대상 테스트만 실행한다 (전체가 아닌). 패키지 매니저는 Phase 1에서 감지된 값 사용.

```bash
pnpm exec playwright test {대상 spec 경로} --reporter=list --trace=on
# 또는
npx playwright test {대상 spec 경로} --reporter=list --trace=on
```

`--trace=on`을 강제로 활성화 (자가 복구의 입력으로 필수).

**Bash 실행 시 주의**:
- timeout은 기본보다 길게 (E2E는 3~5분도 정상)
- stdout/stderr 둘 다 캡처
- exit code 확인 (0: 통과, 비제로: 실패)

---

## Step 2. 통과 처리

exit code 0이면:

```
✅ Phase 3 완료: 테스트 통과
  - 대상: e2e/tests/agent/specs/create.spec.ts
  - 실행 시간: 12.4초
  - 시도 횟수: 1

다음 단계 안내:
- 추가 시나리오 생성: 자연어로 요청
- VRT 추가: "VRT 붙여줘"
- CI 추가: "E2E CI 워크플로우 추가해줘"
```

루프 종료.

---

## Step 3. 실패 시 컨텍스트 수집

다음을 수집해 Self-Healer에게 전달할 준비를 한다:

1. **실패한 테스트 파일 경로와 내용** (Read)
2. **참조하는 flow 파일** (있는 경우 Read)
3. **참조하는 Helper 파일** — selector 관련 실패면 해당 Helper Read
4. **Playwright 에러 메시지 전문** (Bash 출력에서 추출)
5. **trace 스크린샷 경로** — `test-results/.../trace.zip` 또는 첨부 screenshot
   - 가능하면 trace를 풀어 핵심 screenshot 파일 경로 확보
   - `playwright-report/data/*.png` 도 후보
6. **콘솔 로그** (있는 경우)

스크린샷은 Read 도구가 이미지를 받을 수 있으므로 **Healer에게 image input으로 전달**한다.

---

## Step 4. Self-Healer 디스패치

`assets/prompts/self-healer.md` 의 프롬프트로 `general-purpose` 서브에이전트 호출.

**전달 컨텍스트** (프롬프트 내부에 모두 포함):
- Step 3에서 수집한 정보 전부
- `references/selector-priority.md` 전문 임베드
- `references/failure-classification.md` 전문 임베드
- `references/helper-templates.md` 의 Helper 시그니처 카탈로그
- 자연어→코드 매핑 규칙 (`SKILL.md`에서 복사)

```text
Agent({
  description: "Analyze Playwright test failure and propose fix",
  subagent_type: "general-purpose",
  prompt: <assets/prompts/self-healer.md + 위 컨텍스트>
})
```

---

## Step 5. Healer 응답 검토

Healer는 다음 구조로 응답한다 (메인 스레드가 파싱):

```yaml
classification: UI_CHANGE | TEST_BUG | APP_BUG | ENV_ISSUE
confidence: 0.0 ~ 1.0
reasoning: |
  <2-3문장 분류 근거>
patch: |
  <unified diff>     # APP_BUG/ENV_ISSUE는 null
notes_to_user: |
  <보고용 메시지>
```

### 분기 처리

**UI_CHANGE 또는 TEST_BUG**:
- `confidence ≥ 0.5` → 패치 적용 후 재실행 (시도 횟수 +1)
- `confidence < 0.5` → 사용자에게 patch와 reasoning을 보여주고 `AskUserQuestion`으로 적용 여부 확인

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
  - [ ] 개발 서버 기동 여부
  - [ ] .env 환경변수
  - [ ] mock 핸들러 등록 여부
  
  환경 보정 후 다음 명령으로 재시도:
    pnpm exec playwright test {대상}
  ```

---

## Step 6. 패치 적용

`patch` 필드의 unified diff를 Edit 도구로 적용한다.

**적용 전 안전 확인**:
- diff 대상 파일이 존재하는지 확인
- diff의 hunk가 실제 파일 내용과 매칭하는지 확인 (Read로 검증)
- 매칭 실패 시 사용자에게 patch와 함께 수동 적용 요청

**적용 후**:
- 시도 횟수를 1 증가
- Step 1로 돌아가 재실행

---

## Step 7. 3회 한도 도달

시도 횟수가 3에 도달하면 루프 종료. 최종 보고:

```
❌ Phase 3 종료: 3회 시도 후에도 실패

대상: e2e/tests/agent/specs/create.spec.ts

시도 이력:
1. UI_CHANGE (conf 0.7) → 패치 적용 (FormHelper.submit label)
2. TEST_BUG (conf 0.6) → 패치 적용 (대기 추가)
3. UI_CHANGE (conf 0.4) → confidence 낮아 미적용, 사용자 검토 필요

최종 trace: test-results/.../trace.zip
마지막 가설: <Healer의 마지막 reasoning>

다음 시도 옵션:
- 마지막 patch 직접 검토 및 적용
- 앱 코드 확인 (APP_BUG 의심 시)
- 환경 점검 (ENV_ISSUE 의심 시)
- 새 자연어 시나리오로 재시도
```

---

## 안전 가드

- **APP_BUG / ENV_ISSUE는 절대 자동 수정하지 않는다** — 분류가 그렇게 나오면 무조건 보고만.
- **단언 값(`toBe(...)`, `toContain(...)`)을 함부로 바꾸지 않는다** — 단언 값 변경은 보통 APP_BUG의 신호. 의심되면 사용자에게.
- **mock 응답 데이터를 함부로 바꾸지 않는다** — fixture는 의도된 데이터. 변경 필요하면 사용자에게.
- **3회 한도는 절대 넘기지 않는다** — 무한 루프 방지.

---

## 보고서 메모

각 시도의 분류·patch 요약을 메인 스레드에서 보관해, 최종 보고에 포함한다. 이를 통해 사용자는 "어떤 가설로 어떻게 수정했는지" 추적할 수 있다.
