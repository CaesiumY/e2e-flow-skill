# Contributing to e2e-flow-skill

기여 환영합니다. 이 문서는 변경 사항을 안전하게 반영하기 위한 가이드입니다.

## 단일 출처(SoT) 원칙

스킬의 모든 규칙·코드는 `skills/e2e-flow/` 안에만 존재합니다.

- 규칙(Selector 우선순위, 실패 분류)은 `skills/e2e-flow/references/` 에 한 번만 정의
- 페이즈 절차서는 규칙을 *Read 지시*로 참조 (중복 임베드 금지, 단 서브에이전트 프롬프트는 예외)
- 코드 템플릿은 `skills/e2e-flow/assets/templates/*.tmpl` 에만 존재

변경 시 단일 출처를 우선 고치고, 의존 위치(서브에이전트 프롬프트 등)에 전파합니다.

---

## 변경 시 체크리스트

### 1. 새 Helper 추가

예: `FileUploadHelper` 추가 시.

- [ ] `skills/e2e-flow/references/helper-templates.md` 에 클래스 코드 + 사용 예 추가
- [ ] `skills/e2e-flow/assets/templates/helpers/FileUploadHelper.ts.tmpl` 작성
- [ ] `skills/e2e-flow/assets/templates/fixtures.ts.tmpl` 의 `Helpers` 인터페이스에 추가
- [ ] `skills/e2e-flow/references/phase-1-setup.md` 의 생성 파일 목록에 추가
- [ ] `skills/e2e-flow/SKILL.md` 의 파일 구조 컨벤션 + 자연어→코드 매핑에 추가
- [ ] `README.md` 의 Helper 9종 표 갱신 (개수 N종으로)

### 2. Selector 우선순위 규칙 변경

- [ ] `skills/e2e-flow/references/selector-priority.md` 만 수정
- [ ] 영향 검토: 변경된 규칙이 `skills/e2e-flow/assets/prompts/self-healer.md` 안에도 임베드되어 있으므로 같이 갱신
- [ ] `skills/e2e-flow/SKILL.md` 의 공통 규칙 섹션 요약과 일치하는지 확인

### 3. 실패 분류 기준 변경

- [ ] `skills/e2e-flow/references/failure-classification.md` 만 수정
- [ ] `skills/e2e-flow/assets/prompts/self-healer.md` 의 임베드 사본도 갱신 (서브에이전트는 컨텍스트 격리 때문에 사본이 필요)
- [ ] `README.md` 의 4분류 요약 표 일치 확인

### 4. 새 페이즈 추가 / 페이즈 절차 변경

- [ ] `skills/e2e-flow/references/phase-N-*.md` 작성/수정
- [ ] `skills/e2e-flow/SKILL.md` 의 페이즈 라우팅 표 갱신
- [ ] `skills/e2e-flow/SKILL.md` 의 페이즈 진입 체크리스트 갱신
- [ ] `README.md` 의 파이프라인 표 갱신

### 5. 코드 템플릿 변경

- [ ] `skills/e2e-flow/assets/templates/*.tmpl` 직접 수정
- [ ] 치환 플레이스홀더(`{{...}}`)가 새로 도입되면 `skills/e2e-flow/references/phase-1-setup.md` 의 치환 규칙 표에 추가

### 6. CI 워크플로우 템플릿 변경

`assets/templates/ci/playwright-e2e.yml.tmpl` 은 게이팅 로직을 담고 있어 회귀가 조용히 통과합니다.

- [ ] 템플릿 수정 후 **렌더링 → YAML 파싱** 확인 (미치환 `{{}}` 0건 + `yaml.safe_load` 통과)
- [ ] 티어 결정 스크립트를 바꿨다면 **결정 표 전 행을 재검증** — 특히 `e2e:full-stack` 부분 문자열
      오매치, 변경 파일 0개, `merge_group` 의 빈 env 값
- [ ] **"부재가 통과로 집계되는 지점"을 다시 확인**:
      개수 측정 스텝의 `--pass-with-no-tests`, 0-매칭 시 full 승격, gate 의 "skipped = 성공" 조건
      (tier=skip 또는 total=0 일 때만 허용)
- [ ] 개수 측정과 실행 스텝이 **동일한** `--grep` / 경로 / `--project` 인자를 쓰는지
- [ ] 사용자 제어 입력(라벨명·파일명·`ci-scope.json` 키)이 `run:` 에 `${{ }}` 로 직접 보간되지 않고
      `env:` 를 경유하는지
- [ ] 치환 플레이스홀더를 추가/삭제했다면 `references/phase-4-enhance.md` 4.2.2 표와
      `references/phase-1-setup.md` Step 4 표에 반영
- [ ] `README.md` 의 티어 표 갱신

### 7. 설치 스크립트 변경

- [ ] `install.sh` 와 `install.ps1` 양쪽을 함께 수정 (피처 패리티 유지)
- [ ] 새 옵션 도입 시 `README.md` 의 "설치 옵션" 표 갱신
- [ ] 로컬에서 양쪽 OS 환경에서 검증 (최소: 새 머신/VM에 설치 → `~/.claude/skills/e2e-flow/SKILL.md` 존재 확인)

---

## 검증 절차

PR 제출 전 다음을 수행해주세요.

### 셀프 구조 검증

```bash
# 모든 reference 경로가 유효한지 (TODO/FIXME/dead reference 없음)
grep -r "TODO\|FIXME\|TBD" skills/

# 인명/회사명/블로그 출처 없음 (정책)
grep -ri "블로그\|이효린\|올라핀\|allra\|hyorish" skills/ README.md
```

두 명령 모두 매칭 0건이어야 합니다.

CI 템플릿을 건드렸다면 렌더링·파싱까지 확인합니다 (미치환 토큰이 있으면 GitHub 에서만 깨집니다):

```bash
grep -rhoE '\{\{[A-Z_]+\}\}' skills/e2e-flow/assets/templates/ | sort -u
```

### 통합 검증 (시간 여유 있을 때)

새 빈 Next.js 프로젝트에서 워크스루:

```bash
npx create-next-app@latest test-target
cd test-target
# 본 레포 install.sh 로 스킬 설치
bash /path/to/e2e-flow-skill/install.sh
# Claude Code 실행 후 시나리오 수행:
#  1) "Playwright E2E 셋업해줘"
#  2) "메인 페이지에 들어가서 로고가 보이는지 확인하는 테스트 만들어줘"
#  3) Helper 한 줄 깨뜨린 후 재호출 → 자가 복구 동작 확인
#  4) "VRT 붙여줘"
#  5) "CI 워크플로우 추가해줘"
#  6) 생성된 .github/workflows/playwright.yml 의 decide job 로직을 결정 표와 대조
```

각 단계에서 의도한 산출물이 생성되는지 확인합니다.

---

## 커밋 메시지

[Conventional Commits](https://www.conventionalcommits.org/) 스타일 권장:

```
feat(helpers): add FileUploadHelper for design system file inputs
fix(self-healer): tighten APP_BUG classification threshold
docs(readme): refresh install instructions for skills CLI
refactor(templates): split fixtures.ts.tmpl into smaller hunks
```

타입:
- `feat`: 새 기능 (Helper, 페이즈, 규칙 등)
- `fix`: 버그 수정
- `docs`: 문서 변경
- `refactor`: 구조 개선 (동작 변경 없음)
- `chore`: 빌드/설치/잡일

---

## PR 가이드

- **하나의 PR = 하나의 변경 단위.** Helper 추가 + 규칙 변경 + 설치 스크립트 수정을 한 PR에 묶지 마세요.
- **변경 의도를 PR 본문에 짧게 적어주세요** — "왜" 가 코드보다 휘발성 강합니다.
- 큰 변경은 issue로 먼저 논의 권장.

---

## 라이선스

MIT 라이선스에 기여합니다. PR 제출은 본인이 작성했거나 호환 라이선스로 배포 가능한 코드라는 동의로 간주됩니다.
