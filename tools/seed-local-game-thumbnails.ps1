param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$gamesRoot = Join-Path $repoRoot "games"
$thumbRoot = Join-Path $repoRoot "assets\game-thumbs"

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Read-JsonFile([string]$Path) {
  $raw = [System.IO.File]::ReadAllText($Path)
  if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) {
    $raw = $raw.Substring(1)
  }
  return $raw | ConvertFrom-Json
}

function Write-Utf8Json([string]$Path, $Value) {
  $json = [string]($Value | ConvertTo-Json -Depth 10)
  [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Normalize-Key([string]$Value) {
  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) {
    return ""
  }

  $text = $text.ToLowerInvariant()
  $text = $text.Replace("&", "and")
  $text = [regex]::Replace($text, "[^a-z0-9]+", "")
  return $text
}

Ensure-Dir $thumbRoot

$thumbMap = @(
  @{
    output = "1v1lol.png"
    source = "C:\Users\Raahim\truffled-temp\games\1v1lol\logo.png"
    aliases = @("1v1lol", "1v1-lol")
  },
  @{
    output = "2048.png"
    source = "C:\Users\Raahim\truffled-temp\games\2048\thumb.png"
    aliases = @("2048")
  },
  @{
    output = "bitlife.png"
    source = "C:\Users\Raahim\truffled-temp\games\bitlife\logo.png"
    aliases = @("bitlife")
  },
  @{
    output = "cookie-clicker.png"
    source = "C:\Users\Raahim\truffled-temp\games\cookie-clicker\logo.png"
    aliases = @("cookieclicker", "cookie-clicker")
  },
  @{
    output = "drive-mad.jpg"
    source = "C:\Users\Raahim\truffled-temp\games\drive-mad\logo.jpg"
    aliases = @("drivemad", "drive-mad")
  },
  @{
    output = "gun-mayhem.png"
    source = "C:\Users\Raahim\truffled-temp\games\funmayhem\icon.png"
    aliases = @("funmayhem", "gunmayhem", "gun-mayhem")
  },
  @{
    output = "idle-breakout.png"
    source = "C:\Users\Raahim\truffled-temp\games\idle-breakout\img\thumbnail.png"
    aliases = @("idlebreakout", "idle-breakout")
  },
  @{
    output = "paperio2.png"
    source = "C:\Users\Raahim\truffled-temp\games\paperio2\images\logo.png"
    aliases = @("paperio2", "paper-io-2")
  },
  @{
    output = "retro-bowl.jpg"
    source = "C:\Users\Raahim\truffled-temp\games\retro-bowl\img\icon.jpg"
    aliases = @("retrobowl", "retro-bowl")
  },
  @{
    output = "sm64.png"
    source = "C:\Users\Raahim\truffled-temp\games\sm64\logo.png"
    aliases = @("sm64")
  },
  @{
    output = "soccer-random.jpg"
    source = "C:\Users\Raahim\truffled-temp\games\soccer-random\banner.jpg"
    aliases = @("soccerrandom", "soccer-random")
  },
  @{
    output = "superhot.png"
    source = "C:\Users\Raahim\truffled-temp\games\superhot\icon.png"
    aliases = @("superhot")
  },
  @{
    output = "tetris.png"
    source = "C:\Users\Raahim\truffled-temp\games\tetris\icon.png"
    aliases = @("tetris")
  },
  @{
    output = "tiny-fishing.png"
    source = "C:\Users\Raahim\truffled-temp\games\tiny-fishing\thumb.png"
    aliases = @("tinyfishing", "tiny-fishing")
  },
  @{
    output = "vex.png"
    source = "C:\Users\Raahim\truffled-temp\games\vex\icon.png"
    aliases = @("vex")
  }
)

$thumbnailByAlias = @{}
foreach ($item in $thumbMap) {
  if (-not (Test-Path $item.source)) {
    continue
  }

  $targetPath = Join-Path $thumbRoot $item.output
  Copy-Item -Path $item.source -Destination $targetPath -Force

  foreach ($alias in $item.aliases) {
    $thumbnailByAlias[(Normalize-Key $alias)] = "/assets/game-thumbs/$($item.output)"
  }
}

$updated = 0
Get-ChildItem $gamesRoot -Directory | ForEach-Object {
  $manifestPath = Join-Path $_.FullName "games.json"
  if (-not (Test-Path $manifestPath)) {
    return
  }

  $entries = @(
    Read-JsonFile $manifestPath
  )

  $changed = $false
  foreach ($entry in $entries) {
    $normalizedSlug = Normalize-Key $entry.slug
    if (-not $thumbnailByAlias.ContainsKey($normalizedSlug)) {
      continue
    }

    $thumbUrl = $thumbnailByAlias[$normalizedSlug]
    if ($entry.PSObject.Properties["thumbnailUrl"] -and [string]$entry.thumbnailUrl -eq $thumbUrl) {
      continue
    }

    $entry | Add-Member -NotePropertyName thumbnailUrl -NotePropertyValue $thumbUrl -Force
    $changed = $true
    $updated += 1
  }

  if ($changed) {
    Write-Utf8Json -Path $manifestPath -Value $entries
  }
}

Write-Output ("updated_entries=" + $updated)
