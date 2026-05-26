# e2e-flow-skill installer (Windows PowerShell 5.1+ / PowerShell 7+)
#
# Installs the e2e-flow skill (auto-pipeline verified on Claude Code; content
# reusable elsewhere). Trigger-based; no CLAUDE.md merge.
#
# Usage:
#   irm https://raw.githubusercontent.com/CaesiumY/e2e-flow-skill/main/install.ps1 | iex
#   iex "& { $(irm https://raw.githubusercontent.com/CaesiumY/e2e-flow-skill/main/install.ps1) } -Target project"
#   iex "& { $(irm https://raw.githubusercontent.com/CaesiumY/e2e-flow-skill/main/install.ps1) } -Ref v1.2.3"

[CmdletBinding()]
param(
  [ValidateSet('global', 'project')]
  [string]$Target = 'global',

  [string]$Ref = 'main',

  [string]$SkillDir = ''
)

$ErrorActionPreference = 'Stop'

$Repo = 'CaesiumY/e2e-flow-skill'
$SkillName = 'e2e-flow'

# 설치 경로 결정
if ($SkillDir) {
  $SkillsDir = $SkillDir
}
elseif ($Target -eq 'project') {
  $SkillsDir = Join-Path (Get-Location) '.claude\skills'
}
else {
  $SkillsDir = Join-Path $env:USERPROFILE '.claude\skills'
}

# 임시 작업 디렉터리
$WorkDir = Join-Path ([IO.Path]::GetTempPath()) ("e2e-flow-skill-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

try {
  $TarballUrl = "https://codeload.github.com/$Repo/zip/$Ref"
  $ZipPath = Join-Path $WorkDir 'repo.zip'
  Write-Host "↓ downloading $Repo@$Ref"
  Invoke-WebRequest -Uri $TarballUrl -OutFile $ZipPath -UseBasicParsing

  Expand-Archive -Path $ZipPath -DestinationPath $WorkDir -Force

  $Extracted = Get-ChildItem -Path $WorkDir -Directory | Where-Object { $_.Name -like 'e2e-flow-skill-*' } | Select-Object -First 1
  if (-not $Extracted) {
    throw "extracted dir 'e2e-flow-skill-*' not found in $WorkDir"
  }

  $SrcPath = Join-Path $Extracted.FullName "skills\$SkillName"
  if (-not (Test-Path $SrcPath)) {
    throw "skills\$SkillName not found in tarball"
  }

  if (-not (Test-Path $SkillsDir)) {
    New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null
  }

  $DestPath = Join-Path $SkillsDir $SkillName
  if (Test-Path $DestPath) {
    Write-Host "↺ existing install detected at $DestPath — replacing"
    Remove-Item -Recurse -Force $DestPath
  }

  Copy-Item -Recurse $SrcPath $DestPath
  Write-Host "✔ installed $SkillName -> $DestPath\"

  Write-Host @"

Done.

Trigger phrases (자연어로 호출하면 자동 발동):
  - "Playwright 셋업해줘", "E2E 테스트 추가해줘"
  - "이 페이지 테스트 만들어줘"
  - "테스트 깨졌어 고쳐줘"
  - "VRT 붙여줘", "E2E CI 워크플로우 추가해줘"

스킬 위치: $DestPath\
SKILL.md:  $DestPath\SKILL.md
"@
}
finally {
  if (Test-Path $WorkDir) {
    Remove-Item -Recurse -Force $WorkDir
  }
}
