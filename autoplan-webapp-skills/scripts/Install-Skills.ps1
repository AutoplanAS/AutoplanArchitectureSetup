param(
  [string]$TargetRoot = (Join-Path $HOME ".agents\skills"),
  [ValidateSet("copy", "link")]
  [string]$Mode = "copy"
)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$packageRoot = Split-Path -Parent $scriptRoot
$skillsRoot = Join-Path $packageRoot "skills"

if (-not (Test-Path $skillsRoot)) {
  throw "Skills source folder not found: $skillsRoot"
}

$skills = Get-ChildItem -Path $skillsRoot -Directory | Where-Object { $_.Name -like "autoplan-webapp-*" } | Sort-Object Name
if (-not $skills -or $skills.Count -eq 0) {
  throw "No autoplan-webapp-* skills found in $skillsRoot"
}

if (-not (Test-Path $TargetRoot)) {
  New-Item -Path $TargetRoot -ItemType Directory -Force | Out-Null
}

Write-Host "Installing $($skills.Count) skills to $TargetRoot in $Mode mode..."

foreach ($skill in $skills) {
  $targetPath = Join-Path $TargetRoot $skill.Name

  if (Test-Path $targetPath) {
    Remove-Item -Path $targetPath -Recurse -Force
  }

  if ($Mode -eq "link") {
    try {
      New-Item -ItemType SymbolicLink -Path $targetPath -Target $skill.FullName -ErrorAction Stop | Out-Null
      Write-Host "Linked: $($skill.Name)"
      continue
    } catch {
      Write-Warning "Failed to create symlink for $($skill.Name). Falling back to copy mode."
    }
  }

  Copy-Item -Path $skill.FullName -Destination $targetPath -Recurse -Force
  Write-Host "Copied: $($skill.Name)"
}

Write-Host "Done."

