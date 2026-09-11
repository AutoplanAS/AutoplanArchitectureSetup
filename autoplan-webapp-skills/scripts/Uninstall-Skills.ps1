param(
  [string]$TargetRoot = (Join-Path $HOME ".agents\skills")
)

$skillNames = @(
  "autoplan-webapp-architecture",
  "autoplan-webapp-frontend-react",
  "autoplan-webapp-api-node",
  "autoplan-webapp-auth-data",
  "autoplan-webapp-testing-quality",
  "autoplan-webapp-deployment-hybrid"
)

if (-not (Test-Path $TargetRoot)) {
  Write-Host "Target folder does not exist: $TargetRoot"
  return
}

foreach ($name in $skillNames) {
  $path = Join-Path $TargetRoot $name
  if (Test-Path $path) {
    Remove-Item -Path $path -Recurse -Force
    Write-Host "Removed: $name"
  }
}

Write-Host "Done."

