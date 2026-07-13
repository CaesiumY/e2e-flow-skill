# Self-Healer 실패 분류 기준

Phase 3(자가 복구)에서 테스트 실패의 원인을 4가지 중 하나로 분류한다. 모든 실패를 무작정 고치면 **앱의 실제 버그를 테스트 수정으로 덮어버리는 위험**이 있으므로, 명시적 분류 기준으로 어떤 실패는 고치고 어떤 실패는 보고만 할지 결정한다.

---

## 분류 대상 전제 (사전 필터)

TS 컴파일 에러(`TS####`), `SyntaxError`, `Cannot find module` 등 **정적 결함 신호는 이 4분류 대상이 아니다.** 이런 실패는 Self-Healer를 디스패치하지 않고, **Phase 3 사전 필터에서 메인 스레드가 import 경로·시그니처를 직접 수정**한다 (`references/phase-3-self-heal.md` Step 1.5). Self-Healer에 도달하는 실패는 정적 결함이 걸러진 **런타임·단언·selector 실패**로 한정된다.

---

## 4분류 매트릭스

| 분류 | 의미 | 일반적 신호 | Healer 행동 |
|---|---|---|---|
| **UI_CHANGE** | UI가 의도적으로 변경되어 selector가 더 이상 맞지 않음 | trace에서 새 UI가 보임, 버튼 텍스트·역할·구조가 달라짐 | **selector 또는 Helper 내부 수정** |
| **TEST_BUG** | 테스트 코드 자체 결함 | strict mode 위반, 비동기 대기 부족, 영역 스코프 누락, 잘못된 단언 | **테스트 코드 수정** |
| **APP_BUG** | 앱의 실제 결함 (테스트는 정상) | 검증 단계에서 기대값과 실제값의 의미 있는 차이, 콘솔 에러, 서버 응답이 명세와 다름 | **수정 금지. 사용자 보고** |
| **ENV_ISSUE** | 인프라/환경 문제 | 서버 미기동(ECONNREFUSED), 타임아웃, 인증 토큰 만료, 모킹 미적용 | **수정 금지. 사용자 보고** |

---

## 각 분류의 판단 신호

### UI_CHANGE

**trace 스크린샷·에러 메시지 신호**:
- "locator resolved to 0 elements" + trace에서 새로운 UI가 보임
- 버튼 텍스트가 trace의 실제 텍스트와 다름 (예: 코드 `'저장'` vs trace `'등록'`)
- ARIA role이 변경됨 (예: `button` → `link`)
- 컴포넌트가 다른 위치로 이동함

**Healer 동작**:
1. trace 스크린샷에서 현재 UI를 확인
2. **Selector 우선순위 규칙**(self-healer.md 내장 축약본)에 따라 새 selector 선택
3. Helper 내부에서 사용하는 selector면 **Helper만 수정**(파급 최소화), spec 본문이면 spec 수정
4. 수정 내용을 EDIT 블록으로 반환 (`edits_count` 포함)

**예시 변경 (OLD → NEW)**:
```diff
- async submit(label = '저장') {
+ async submit(label = '등록') {
    await this.page.getByRole('button', { name: label }).click();
  }
```

### TEST_BUG

**에러 메시지 신호**:
- "strict mode violation: ... resolved to N elements" (영역 스코프 누락)
- "Timeout exceeded waiting for ..." 인데 trace에서 요소가 결국 나타남 (대기 부족)
- "Expected X but received Y" 단, Y가 의도된 값이고 X가 잘못된 단언인 경우
- `nth(0)` / `first()` 사용으로 의미 불명확한 selector

**Healer 동작**:
1. 에러 종류 식별
2. Selector 우선순위 규칙에 따라 수정 방향 결정:
   - strict mode 위반 → 영역 스코프 추가 또는 더 구체적인 name 사용
   - 대기 부족 → 명시적 `expect(...).toBeVisible()` 추가, `waitFor*` 보강
   - 잘못된 단언 → 단언 값을 trace 기준으로 수정 (단, 의도된 검증값을 함부로 바꾸지 않는다 — 의심되면 APP_BUG로 분류)
3. 수정 내용을 EDIT 블록으로 반환

**예시 변경 — strict mode 위반**:
```diff
- page.getByRole('tabpanel').locator('input[type="text"]').fill('값');
+ page.getByRole('tabpanel').getByPlaceholder('검색어를 입력하세요').fill('값');
```

**예시 변경 — 대기 부족**:
```diff
+ await expect(dialog.getByRole('button', { name: '확인' })).toBeEnabled();
  await dialog.getByRole('button', { name: '확인' }).click();
```

### APP_BUG

**판단 신호**:
- 검증 단언(`expect(...).toContain(...)`, `toBe(...)`)이 실패했고, trace의 실제 결과가 **명백히 잘못된 동작**
- 콘솔에 앱 측 에러 로그 (`Uncaught TypeError`, React error boundary 등)
- 서버 응답이 OpenAPI/명세와 다름
- 클릭 후 페이지 전환·모달 열림 등 부수효과가 발생하지 않음

**Healer 동작**:
1. **절대 코드를 수정하지 않는다**
2. 다음 정보를 `notes_to_user`에 정리해 반환:
   - 어떤 단언/플로우가 실패했는지
   - trace 경로 (스크린샷·HAR 첨부)
   - 의심되는 앱 코드 위치 (가능하면)
   - 재현 절차

### ENV_ISSUE

**판단 신호**:
- 네트워크 에러: `ECONNREFUSED`, `net::ERR_*`
- "Test timed out" 인데 trace가 비어 있거나 페이지가 비어 있음 (서버 미응답)
- 인증/세션 만료 응답 (401, 403)
- mock 설정 미적용으로 실서버로 요청이 나감
- 브라우저 실행 실패 (`browserType.launch` 에러)

**Healer 동작**:
1. **절대 코드를 수정하지 않는다**
2. 다음을 `notes_to_user`에 정리:
   - 어떤 환경 문제가 의심되는지
   - 사용자가 확인할 항목 체크리스트 (서버 기동, `.env`, mock 핸들러 등록 여부)
   - 환경 보정 후 재실행 명령어

---

## Healer 출력 형식

서브에이전트는 **YAML 헤더 + `edits_count` 개수만큼의 EDIT 블록**으로 응답한다 (메인 스레드가 파싱). EDIT 블록의 정확한 형식은 `assets/prompts/self-healer.md`의 출력 계약이 단일 출처다.

```yaml
classification: UI_CHANGE | TEST_BUG | APP_BUG | ENV_ISSUE
confidence: 0.0 ~ 1.0
reasoning: |
  <2-3문장으로 분류 근거>
edits_count: 0   # 뒤따르는 EDIT 블록 개수. APP_BUG/ENV_ISSUE는 반드시 0
notes_to_user: |
  <APP_BUG/ENV_ISSUE인 경우 사용자에게 전달할 메시지. 그 외는 짧은 요약>
```

`confidence < 0.5`이거나 오케스트레이터 재검 게이트(`references/phase-3-self-heal.md` Step 5.0)에 걸리면 메인 스레드는 edits를 적용하지 않고 사용자에게 검토를 요청한다.

---

## 분류 모호 시 우선순위

여러 분류가 동시에 가능해 보일 때:

1. 단언 실패 + 실제 값이 의심스러우면 → **APP_BUG로 분류**, 사용자에게 결정 위임 (안전 측)
2. selector 매칭 0개 + trace에 새 UI → **UI_CHANGE**
3. selector 매칭 N개 (strict mode) → **TEST_BUG**
4. 네트워크/타임아웃 신호와 다른 신호 혼재 → **ENV_ISSUE** (환경부터 점검)

원칙: **수정 금지 분류(APP_BUG / ENV_ISSUE)로 기울 때는 그 쪽을 택한다.** 잘못 수정하는 비용이 잘못 보고하는 비용보다 크다.
