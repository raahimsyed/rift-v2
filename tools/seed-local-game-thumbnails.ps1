param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$gamesRoot = Join-Path $repoRoot "games"
$thumbRoot = Join-Path $repoRoot "assets\game-thumbs"
$publicRoot = "C:\Users\Raahim\rift\public"
$mirrorRoot = "C:\Users\Raahim\truffled-temp"
$manifestPath = "C:\Users\Raahim\rift\data\truffled-root-manifest.json"

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

function Normalize-PathFragment([string]$Value) {
  return ([string]$Value).Trim().TrimStart("/") -replace "/", "\"
}

function Get-FileStem([string]$Path) {
  return [System.IO.Path]::GetFileNameWithoutExtension([string]$Path)
}

function Add-Alias([hashtable]$Table, [string]$Alias, [string]$Value, [bool]$Force = $false) {
  $key = Normalize-Key $Alias
  if ([string]::IsNullOrWhiteSpace($key)) {
    return
  }
  if ($Force -or -not $Table.ContainsKey($key)) {
    $Table[$key] = $Value
  }
}

function Get-RelativeImageRefs([string]$Html) {
  $refs = New-Object System.Collections.Generic.List[string]
  $patterns = @(
    '(?is)<meta[^>]+(?:property|name)=["''](?:og:image|twitter:image|twitter:image:src)["''][^>]+content=["'']([^"'']+)["'']',
    '(?is)<link[^>]+rel=["''][^"'']*(?:icon|apple-touch-icon|shortcut icon)[^"'']*["''][^>]+href=["'']([^"'']+)["'']',
    '(?is)thumbnail\s*:\s*["'']([^"'']+)["'']',
    '(?is)<img[^>]+(?:src|data-cfsrc)=["'']([^"'']+)["''][^>]*class=["''][^"'']*(?:logo|cover|thumbnail|splash)[^"'']*["'']',
    '(?is)<img[^>]+class=["''][^"'']*(?:logo|cover|thumbnail|splash)[^"'']*["''][^>]+(?:src|data-cfsrc)=["'']([^"'']+)["'']'
  )

  foreach ($pattern in $patterns) {
    foreach ($match in [regex]::Matches($Html, $pattern)) {
      $value = [string]$match.Groups[1].Value
      if (-not [string]::IsNullOrWhiteSpace($value)) {
        $refs.Add($value.Trim()) | Out-Null
      }
    }
  }

  return @($refs | Select-Object -Unique)
}

function Resolve-WrapperRef([string]$WrapperFile, [string]$TargetPath, [string]$Ref) {
  $clean = [string]$Ref
  if ([string]::IsNullOrWhiteSpace($clean)) {
    return $null
  }

  $clean = $clean.Trim()
  if ($clean.StartsWith("data:") -or $clean.StartsWith("javascript:")) {
    return $null
  }

  if ($clean -match '^https?://') {
    return [pscustomobject]@{
      type = "remote"
      value = $clean
      basename = [System.IO.Path]::GetFileName(($clean -split '[?#]')[0])
      ref = $clean
    }
  }

  $fragment = Normalize-PathFragment $clean
  if ([string]::IsNullOrWhiteSpace($fragment)) {
    return $null
  }

  $candidates = New-Object System.Collections.Generic.List[string]
  $candidates.Add((Join-Path $publicRoot $fragment)) | Out-Null

  if (-not [string]::IsNullOrWhiteSpace($TargetPath)) {
    $targetDir = if ($TargetPath.EndsWith("/")) {
      $TargetPath.TrimEnd("/") -replace "/", "\"
    } else {
      [System.IO.Path]::GetDirectoryName(($TargetPath -replace "/", "\"))
    }

    if (-not [string]::IsNullOrWhiteSpace($targetDir)) {
      $candidates.Add((Join-Path $mirrorRoot (Join-Path $targetDir $fragment))) | Out-Null
    }
  }

  $candidates.Add((Join-Path $mirrorRoot $fragment)) | Out-Null

  foreach ($candidate in ($candidates | Select-Object -Unique)) {
    if (Test-Path $candidate) {
      return [pscustomobject]@{
        type = "local"
        value = $candidate
        basename = [System.IO.Path]::GetFileName($candidate)
        ref = $clean
      }
    }
  }

  return $null
}

function Test-IsGenericThumbnail($Resolved, [string]$WrapperStem) {
  if ($null -eq $Resolved) {
    return $true
  }

  $value = [string]$Resolved.value
  $basename = ([string]$Resolved.basename).ToLowerInvariant()
  $normalizedWrapper = Normalize-Key $WrapperStem
  $normalizedBase = Normalize-Key $basename

  if ($value -match 'truffled-temp\\png\\logo\.(png|svg)$') {
    return $true
  }
  if ($value -match 'rift\\public\\favicon\.ico$') {
    return $true
  }
  if ($value -match '(?i)(loader-logo|webgl-logo|null\.png|apple-touch-icon)') {
    return $true
  }
  if ($basename -match '^(favicon|iconfavicon)\.(ico|png|jpg|jpeg|svg)$' -and $normalizedBase -ne $normalizedWrapper) {
    return $true
  }
  if ($Resolved.type -eq "remote" -and $value -match 'truffled\.lol/png/logo') {
    return $true
  }
  if ($Resolved.type -eq "remote" -and $value -match '/null\.png$') {
    return $true
  }

  return $false
}

function Get-ThumbnailScore($Resolved, [string]$WrapperStem, [string]$TargetPath) {
  $score = 0
  $value = [string]$Resolved.value
  $basename = ([string]$Resolved.basename).ToLowerInvariant()
  $normalizedWrapper = Normalize-Key $WrapperStem
  $normalizedBase = Normalize-Key $basename

  if ($basename -match '(logo|thumb|thumbnail|cover|banner|splash)') {
    $score += 18
  } elseif ($basename -match 'icon') {
    $score += 10
  }

  if ($normalizedBase -and $normalizedWrapper -and ($normalizedBase.Contains($normalizedWrapper) -or $normalizedWrapper.Contains($normalizedBase))) {
    $score += 14
  }

  if ($value -match '(?i)(logo|thumb|thumbnail|cover|banner|splash)') {
    $score += 10
  }

  if ($Resolved.type -eq "local") {
    $score += 12
    try {
      $length = (Get-Item $Resolved.value).Length
      if ($length -ge 10240) {
        $score += 6
      } elseif ($length -ge 4096) {
        $score += 3
      }
    } catch {
    }
  } else {
    $score += 4
  }

  if (-not [string]::IsNullOrWhiteSpace($TargetPath)) {
    $targetNorm = Normalize-Key $TargetPath
    if ($targetNorm.Contains($normalizedWrapper)) {
      $score += 6
    }
  }

  if ($basename -match '^favicon') {
    $score -= 8
  }

  return $score
}

function Get-LocalThumbnailUrl([hashtable]$StoredFiles, [string]$WrapperStem, [string]$SourcePath) {
  $extension = [System.IO.Path]::GetExtension($SourcePath)
  if ([string]::IsNullOrWhiteSpace($extension)) {
    $extension = ".png"
  }

  $outputName = "{0}{1}" -f $WrapperStem.ToLowerInvariant(), $extension.ToLowerInvariant()
  $targetPath = Join-Path $thumbRoot $outputName
  $sourceFullPath = (Resolve-Path $SourcePath).Path

  if (-not $StoredFiles.ContainsKey($sourceFullPath)) {
    Copy-Item -Path $SourcePath -Destination $targetPath -Force
    $StoredFiles[$sourceFullPath] = "/assets/game-thumbs/$outputName"
  }

  return [string]$StoredFiles[$sourceFullPath]
}

function Get-MirrorCandidateScore($Candidate, [string]$Alias) {
  $score = 0
  $basename = ([string]$Candidate.basename).ToLowerInvariant()
  $path = [string]$Candidate.path
  $normalizedAlias = Normalize-Key $Alias
  $normalizedBase = Normalize-Key $basename

  if ($basename -match 'logo') {
    $score += 22
  } elseif ($basename -match '(thumb|thumbnail)') {
    $score += 18
  } elseif ($basename -match '(cover|banner|splash)') {
    $score += 16
  } elseif ($basename -match 'icon') {
    $score += 12
  }

  if ($path -match '(?i)(logo|thumb|thumbnail|cover|banner|splash)') {
    $score += 8
  }

  if ($normalizedAlias -and $normalizedBase -and ($normalizedBase.Contains($normalizedAlias) -or $normalizedAlias.Contains($normalizedBase))) {
    $score += 12
  }

  try {
    $length = (Get-Item $Candidate.path).Length
    if ($length -ge 10240) {
      $score += 6
    } elseif ($length -ge 4096) {
      $score += 3
    }
  } catch {
  }

  switch ([string]$Candidate.source) {
    "truffled-mirror" { $score += 4 }
    "seraph-2048" { $score += 3 }
    "petezah" { $score += 2 }
    "velara" { $score += 1 }
  }

  return $score
}

Ensure-Dir $thumbRoot

$thumbnailByAlias = @{}
$storedFiles = @{}

$manualThumbs = @(
  @{
    source = "C:\Users\Raahim\truffled-temp\games\1v1lol\logo.png"
    output = "1v1lol.png"
    aliases = @("1v1lol", "1v1-lol")
  },
  @{
    source = "C:\Users\Raahim\truffled-temp\games\2048\thumb.png"
    output = "2048.png"
    aliases = @("2048")
  },
  @{
    source = "C:\Users\Raahim\truffled-temp\games\bitlife\logo.png"
    output = "bitlife.png"
    aliases = @("bitlife")
  },
  @{
    source = "C:\Users\Raahim\truffled-temp\games\cookie-clicker\logo.png"
    output = "cookie-clicker.png"
    aliases = @("cookieclicker", "cookie-clicker")
  },
  @{
    source = "C:\Users\Raahim\truffled-temp\games\drive-mad\logo.jpg"
    output = "drive-mad.jpg"
    aliases = @("drivemad", "drive-mad")
  },
  @{
    source = "C:\Users\Raahim\truffled-temp\games\funmayhem\icon.png"
    output = "gun-mayhem.png"
    aliases = @("funmayhem", "gunmayhem", "gun-mayhem")
  },
  @{
    source = "C:\Users\Raahim\truffled-temp\games\idle-breakout\img\thumbnail.png"
    output = "idle-breakout.png"
    aliases = @("idlebreakout", "idle-breakout")
  },
  @{
    source = "C:\Users\Raahim\truffled-temp\games\paperio2\images\logo.png"
    output = "paperio2.png"
    aliases = @("paperio2", "paper-io-2")
  },
  @{
    source = "C:\Users\Raahim\truffled-temp\games\retro-bowl\img\icon.jpg"
    output = "retro-bowl.jpg"
    aliases = @("retrobowl", "retro-bowl")
  },
  @{
    source = "C:\Users\Raahim\truffled-temp\games\sm64\logo.png"
    output = "sm64.png"
    aliases = @("sm64")
  },
  @{
    source = "C:\Users\Raahim\truffled-temp\games\soccer-random\banner.jpg"
    output = "soccer-random.jpg"
    aliases = @("soccerrandom", "soccer-random")
  },
  @{
    source = "C:\Users\Raahim\truffled-temp\games\superhot\icon.png"
    output = "superhot.png"
    aliases = @("superhot")
  },
  @{
    source = "C:\Users\Raahim\truffled-temp\games\tetris\icon.png"
    output = "tetris.png"
    aliases = @("tetris")
  },
  @{
    source = "C:\Users\Raahim\truffled-temp\games\tiny-fishing\thumb.png"
    output = "tiny-fishing.png"
    aliases = @("tinyfishing", "tiny-fishing")
  },
  @{
    source = "C:\Users\Raahim\truffled-temp\games\vex\icon.png"
    output = "vex.png"
    aliases = @("vex")
  }
)

foreach ($item in $manualThumbs) {
  if (-not (Test-Path $item.source)) {
    continue
  }

  $targetPath = Join-Path $thumbRoot $item.output
  Copy-Item -Path $item.source -Destination $targetPath -Force
  $thumbUrl = "/assets/game-thumbs/$($item.output)"
  $storedFiles[(Resolve-Path $item.source).Path] = $thumbUrl

  foreach ($alias in $item.aliases) {
    Add-Alias -Table $thumbnailByAlias -Alias $alias -Value $thumbUrl -Force $true
  }
}

$wrapperManifest = Read-JsonFile $manifestPath
$targetByWrapper = @{}
foreach ($property in $wrapperManifest.map.PSObject.Properties) {
  $targetByWrapper[[string]$property.Value] = [string]$property.Name
}

$autoDiscovered = 0
foreach ($wrapperFile in $wrapperManifest.files) {
  $wrapperPath = Join-Path $publicRoot $wrapperFile
  if (-not (Test-Path $wrapperPath)) {
    continue
  }

  $wrapperStem = Get-FileStem $wrapperFile
  if ($thumbnailByAlias.ContainsKey((Normalize-Key $wrapperStem))) {
    continue
  }

  $html = Get-Content -Raw $wrapperPath
  $refs = Get-RelativeImageRefs $html
  if (-not $refs.Count) {
    continue
  }

  $targetPath = if ($targetByWrapper.ContainsKey($wrapperFile)) { $targetByWrapper[$wrapperFile] } else { "" }
  $best = $null
  foreach ($ref in $refs) {
    $resolved = Resolve-WrapperRef -WrapperFile $wrapperFile -TargetPath $targetPath -Ref $ref
    if ($null -eq $resolved) {
      continue
    }
    if (Test-IsGenericThumbnail -Resolved $resolved -WrapperStem $wrapperStem) {
      continue
    }

    $score = Get-ThumbnailScore -Resolved $resolved -WrapperStem $wrapperStem -TargetPath $targetPath
    if ($score -lt 12) {
      continue
    }

    if ($null -eq $best -or $score -gt $best.score) {
      $best = [pscustomobject]@{
        score = $score
        resolved = $resolved
      }
    }
  }

  if ($null -eq $best) {
    continue
  }

  $thumbUrl = if ($best.resolved.type -eq "local") {
    Get-LocalThumbnailUrl -StoredFiles $storedFiles -WrapperStem $wrapperStem -SourcePath $best.resolved.value
  } else {
    [string]$best.resolved.value
  }

  Add-Alias -Table $thumbnailByAlias -Alias $wrapperStem -Value $thumbUrl
  $autoDiscovered += 1
}

$mirrorRoots = @(
  @{
    name = "truffled-mirror"
    root = "C:\Users\Raahim\truffled-temp\games"
  },
  @{
    name = "seraph-2048"
    root = "C:\Users\Raahim\seraph-2048\games"
  },
  @{
    name = "petezah"
    root = "C:\Users\Raahim\PeteZahGames\public\storage\ag\g"
  },
  @{
    name = "velara"
    root = "C:\Users\Raahim\velara-temp\public\hosted"
  }
)

$mirrorCandidatesByAlias = @{}
foreach ($mirror in $mirrorRoots) {
  if (-not (Test-Path $mirror.root)) {
    continue
  }

  $files = Get-ChildItem -Path $mirror.root -Recurse -File -Include icon.png,icon.jpg,logo.png,logo.jpg,logo.svg,thumb.png,thumb.jpg,thumbnail.png,thumbnail.jpg,cover.png,cover.jpg,splash.png,splash.jpg -ErrorAction SilentlyContinue
  foreach ($file in $files) {
    $relative = $file.FullName.Substring($mirror.root.Length).TrimStart("\")
    if ([string]::IsNullOrWhiteSpace($relative)) {
      continue
    }

    $topLevel = ($relative -split "[\\/]", 2)[0]
    $alias = Normalize-Key $topLevel
    if ([string]::IsNullOrWhiteSpace($alias)) {
      continue
    }

    if (-not $mirrorCandidatesByAlias.ContainsKey($alias)) {
      $mirrorCandidatesByAlias[$alias] = New-Object System.Collections.Generic.List[object]
    }

    $mirrorCandidatesByAlias[$alias].Add([pscustomobject]@{
      source = [string]$mirror.name
      path = $file.FullName
      basename = $file.Name
    }) | Out-Null
  }
}

$mirrorDiscovered = 0
foreach ($alias in $mirrorCandidatesByAlias.Keys) {
  $best = $mirrorCandidatesByAlias[$alias] |
    Sort-Object @{ Expression = { Get-MirrorCandidateScore $_ $alias }; Descending = $true } |
    Select-Object -First 1

  if ($null -eq $best) {
    continue
  }

  $shouldReplace = -not $thumbnailByAlias.ContainsKey($alias)
  if (-not $shouldReplace) {
    $current = [string]$thumbnailByAlias[$alias]
    if ($current -match '^https?://') {
      $shouldReplace = $true
    }
  }

  if (-not $shouldReplace) {
    continue
  }

  $thumbUrl = Get-LocalThumbnailUrl -StoredFiles $storedFiles -WrapperStem $alias -SourcePath $best.path
  Add-Alias -Table $thumbnailByAlias -Alias $alias -Value $thumbUrl -Force $true
  $mirrorDiscovered += 1
}

$updated = 0
Get-ChildItem $gamesRoot -Directory | ForEach-Object {
  $manifestFile = Join-Path $_.FullName "games.json"
  if (-not (Test-Path $manifestFile)) {
    return
  }

  $entries = @(
    Read-JsonFile $manifestFile
  )

  $changed = $false
  foreach ($entry in $entries) {
    $normalizedSlug = Normalize-Key $entry.slug
    if (-not $thumbnailByAlias.ContainsKey($normalizedSlug)) {
      continue
    }

    $thumbUrl = [string]$thumbnailByAlias[$normalizedSlug]
    if ($entry.PSObject.Properties["thumbnailUrl"] -and [string]$entry.thumbnailUrl -eq $thumbUrl) {
      continue
    }

    $entry | Add-Member -NotePropertyName thumbnailUrl -NotePropertyValue $thumbUrl -Force
    $changed = $true
    $updated += 1
  }

  if ($changed) {
    Write-Utf8Json -Path $manifestFile -Value $entries
  }
}

Write-Output ("auto_discovered=" + $autoDiscovered)
Write-Output ("mirror_discovered=" + $mirrorDiscovered)
Write-Output ("updated_entries=" + $updated)
