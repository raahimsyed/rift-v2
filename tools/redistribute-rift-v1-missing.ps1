param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$gamesRoot = Join-Path $repoRoot "games"
$recoveredSlug = "rift-v1-missing"
$recoveredDir = Join-Path $gamesRoot $recoveredSlug
$recoveredManifestPath = Join-Path $recoveredDir "games.json"
$sourcesPath = Join-Path $gamesRoot "sources.json"

function Read-JsonFile([string]$Path) {
  $raw = [System.IO.File]::ReadAllText($Path)
  if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) {
    $raw = $raw.Substring(1)
  }
  return $raw | ConvertFrom-Json
}

function Write-Utf8Json([string]$Path, $Value) {
  $json = [string]($Value | ConvertTo-Json -Depth 8)
  [System.IO.File]::WriteAllText([string]$Path, $json, [System.Text.UTF8Encoding]::new($false))
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

function Get-Tokens([string]$Value) {
  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) {
    return @()
  }

  $text = $text.ToLowerInvariant()
  $text = $text.Replace("&", " and ")
  $text = [regex]::Replace($text, "([a-z])([A-Z])", '$1 $2')
  $text = [regex]::Replace($text, "([a-z])([0-9])", '$1 $2')
  $text = [regex]::Replace($text, "([0-9])([a-z])", '$1 $2')
  $text = [regex]::Replace($text, "[^a-z0-9]+", " ")
  return @($text.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries))
}

function Escape-Html([string]$Value) {
  return [System.Security.SecurityElement]::Escape([string]$Value)
}

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function New-LauncherHtml([string]$LibrarySlug, [string]$LibraryName, $Entry) {
  $title = Escape-Html ("Rift v2 / games / {0} / {1}" -f $LibrarySlug, $Entry.slug)
  $gameName = Escape-Html $Entry.name
  $gameSlug = Escape-Html $Entry.slug
  $sourceUrl = Escape-Html $Entry.sourceUrl
  $sourceBaseUrl = Escape-Html ([string]$Entry.sourceBaseUrl)
  $loadMode = Escape-Html ([string]$Entry.loadMode)
  $libraryLabel = Escape-Html $LibraryName

  return @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$title</title>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
  <link rel="stylesheet" href="../../assets/css/fonts.css">
  <link rel="stylesheet" href="../../assets/css/game-frame.css">
</head>
<body data-library-slug="$LibrarySlug" data-library-name="$libraryLabel" data-game-slug="$gameSlug" data-game-name="$gameName" data-load-mode="$loadMode" data-source-url="$sourceUrl" data-source-base-url="$sourceBaseUrl">
  <header class="topbar">
    <div class="title-block">
      <h1 class="title" id="gameTitle">$gameName</h1>
      <div class="sub" id="gameSub"></div>
    </div>
    <div class="actions">
      <div class="pill fps-pill" id="fpsCounter" aria-live="polite">
        -- fps
      </div>
      <button class="icon-btn" id="backToLibrary" type="button" aria-label="Back to $libraryLabel library">
        <i class="fa-solid fa-arrow-left" aria-hidden="true"></i>
      </button>
    </div>
  </header>

  <main class="stage">
    <iframe id="gameFrame" allow="fullscreen; autoplay; clipboard-read; clipboard-write" referrerpolicy="no-referrer" loading="eager"></iframe>
  </main>

  <script defer src="../../assets/js/game-frame.js"></script>
</body>
</html>
"@
}

$sources = @(
  Read-JsonFile $sourcesPath
)

$libraryNames = @{}
foreach ($source in $sources) {
  $href = [string]$source.localHref
  if ($href -match "^\./([^/]+)/$") {
    $libraryNames[$Matches[1]] = [string]$source.name
  }
}

$libraries = @{}
Get-ChildItem $gamesRoot -Directory | Where-Object { $_.Name -notin @($recoveredSlug, "fnf") } | ForEach-Object {
  $slug = $_.Name
  $gamesJsonPath = Join-Path $_.FullName "games.json"
  if (-not (Test-Path $gamesJsonPath)) {
    return
  }

  $entries = @(
    Read-JsonFile $gamesJsonPath
  )

  $slugSet = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($entry in $entries) {
    if ($entry.slug) {
      [void]$slugSet.Add(([string]$entry.slug).ToLowerInvariant())
    }
  }

  $libraries[$slug] = [pscustomobject]@{
    slug = $slug
    name = if ($libraryNames.ContainsKey($slug)) { $libraryNames[$slug] } else { $slug }
    dir = $_.FullName
    manifestPath = $gamesJsonPath
    entries = [System.Collections.Generic.List[object]]::new()
    slugSet = $slugSet
  }

  foreach ($entry in $entries) {
    $libraries[$slug].entries.Add($entry) | Out-Null
  }
}

$recoveredEntries = @(
  Read-JsonFile $recoveredManifestPath
)

$preference = @(
  "selenite",
  "elite-gamez",
  "ugs",
  "3kh0",
  "seraph",
  "t9lat22",
  "crunchingmath",
  "fyinx",
  "radon",
  "gn-math",
  "ccported",
  "unblockedgames",
  "pokemon",
  "noah",
  "artclass"
)

$preferenceWeight = @{}
for ($i = 0; $i -lt $preference.Count; $i++) {
  $preferenceWeight[$preference[$i]] = 100 - $i
}

$manualTargets = @{
  "30dolar" = "selenite"
  "bbcr" = "selenite"
  "bbp" = "selenite"
  "bfs" = "selenite"
  "donottakethiscathome" = "fyinx"
  "ducklife7" = "elite-gamez"
  "ducklifeadv" = "elite-gamez"
  "falloutt" = "crunchingmath"
  "graybox" = "ugs"
  "jelly" = "t9lat22"
  "karlson2d" = "t9lat22"
  "papaspizza" = "selenite"
  "quakeiii" = "elite-gamez"
  "rbcollege" = "crunchingmath"
  "sfge" = "crunchingmath"
  "slender" = "ugs"
  "slimerancher" = "fyinx"
  "snowrider3d-main" = "selenite"
  "sriddleschool2" = "elite-gamez"
  "srb2" = "t9lat22"
  "survivor" = "3kh0"
  "tattletail" = "fyinx"
  "terraria-wrapper" = "t9lat22"
  "tetrisweeper" = "selenite"
  "time1" = "selenite"
  "timeshoot3" = "selenite"
  "watergirl-1" = "elite-gamez"
  "watergirl-2" = "elite-gamez"
  "watergirl-3" = "elite-gamez"
  "watergirl-4" = "elite-gamez"
  "ween" = "t9lat22"
  "wordle-unlimited" = "selenite"
  "worlds-hardest-game-3" = "3kh0"
}

function Get-PreferenceScore([string]$LibrarySlug) {
  if ($preferenceWeight.ContainsKey($LibrarySlug)) {
    return [double]$preferenceWeight[$LibrarySlug]
  }
  return 0.0
}

function Get-CandidateScore($Entry, [string]$LibrarySlug, $Candidate) {
  $entrySlug = Normalize-Key $Entry.slug
  $entryName = Normalize-Key $Entry.name
  $candidateSlug = Normalize-Key $Candidate.slug
  $candidateName = Normalize-Key $Candidate.name

  $score = 0.0

  if ($entrySlug -and ($entrySlug -eq $candidateSlug -or $entrySlug -eq $candidateName)) {
    $score += 120
  }
  if ($entryName -and ($entryName -eq $candidateName -or $entryName -eq $candidateSlug)) {
    $score += 120
  }
  if ($entrySlug -and $candidateSlug -and (($candidateSlug.Contains($entrySlug)) -or ($entrySlug.Contains($candidateSlug))) -and [Math]::Min($entrySlug.Length, $candidateSlug.Length) -ge 5) {
    $score += 60
  }
  if ($entryName -and $candidateName -and (($candidateName.Contains($entryName)) -or ($entryName.Contains($candidateName))) -and [Math]::Min($entryName.Length, $candidateName.Length) -ge 5) {
    $score += 60
  }

  $entryTokenSet = [System.Collections.Generic.HashSet[string]]::new([string[]](Get-Tokens ("{0} {1}" -f $Entry.slug, $Entry.name)))
  $candidateTokenSet = [System.Collections.Generic.HashSet[string]]::new([string[]](Get-Tokens ("{0} {1}" -f $Candidate.slug, $Candidate.name)))
  foreach ($token in $entryTokenSet) {
    if ($token.Length -lt 3) {
      continue
    }
    if ($candidateTokenSet.Contains($token)) {
      $score += 8
    }
  }

  $sourceUrl = [string]$Entry.sourceUrl
  if ($sourceUrl -match "/gamefile/nowgg/" -and $LibrarySlug -eq "t9lat22") {
    $score += 40
  }
  if ($sourceUrl -match "/gamefile/" -and $LibrarySlug -eq "t9lat22") {
    $score += 18
  }
  if ($sourceUrl -match "/games/" -and $LibrarySlug -eq "elite-gamez") {
    $score += 8
  }

  $score += (Get-PreferenceScore $LibrarySlug) / 100
  return $score
}

function Get-TargetLibrary($Entry, $LibraryMap) {
  $slug = [string]$Entry.slug
  if ($manualTargets.ContainsKey($slug)) {
    return $manualTargets[$slug]
  }

  $fallback = if ([string]$Entry.sourceUrl -match "/gamefile/") { "t9lat22" } else { "elite-gamez" }
  $bestLibrary = $fallback
  $bestScore = -1.0

  foreach ($librarySlug in $LibraryMap.Keys) {
    foreach ($candidate in $LibraryMap[$librarySlug].entries) {
      $score = Get-CandidateScore -Entry $Entry -LibrarySlug $librarySlug -Candidate $candidate
      if ($score -gt $bestScore) {
        $bestScore = $score
        $bestLibrary = $librarySlug
      } elseif ([Math]::Abs($score - $bestScore) -lt 0.0001) {
        if ((Get-PreferenceScore $librarySlug) -gt (Get-PreferenceScore $bestLibrary)) {
          $bestLibrary = $librarySlug
        }
      }
    }
  }

  if ($bestScore -lt 40) {
    return $fallback
  }

  return $bestLibrary
}

$distribution = @{}
foreach ($entry in $recoveredEntries) {
  $targetLibrary = Get-TargetLibrary -Entry $entry -LibraryMap $libraries
  if (-not $distribution.ContainsKey($targetLibrary)) {
    $distribution[$targetLibrary] = [System.Collections.Generic.List[object]]::new()
  }
  $distribution[$targetLibrary].Add($entry) | Out-Null
}

foreach ($librarySlug in $distribution.Keys) {
  $library = $libraries[$librarySlug]
  $libraryDir = $library.dir
  Ensure-Dir $libraryDir

  foreach ($entry in $distribution[$librarySlug]) {
    $finalSlug = ([string]$entry.slug).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($finalSlug)) {
      continue
    }

    $sourceUrl = [string]$entry.sourceUrl
    $duplicate = $false
    foreach ($existing in $library.entries) {
      if ([string]$existing.sourceUrl -eq $sourceUrl) {
        $duplicate = $true
        break
      }
    }
    if ($duplicate) {
      continue
    }

    $suffix = 1
    while ($library.slugSet.Contains($finalSlug)) {
      $suffix++
      $finalSlug = ("{0}-v1-{1}" -f $entry.slug, $suffix).ToLowerInvariant()
    }
    [void]$library.slugSet.Add($finalSlug)

    $finalEntry = [pscustomobject]@{
      slug = $finalSlug
      name = [string]$entry.name
      sourceUrl = [string]$entry.sourceUrl
      sourceBaseUrl = [string]$entry.sourceBaseUrl
      loadMode = [string]$entry.loadMode
    }

    $library.entries.Add($finalEntry) | Out-Null

    $launcherPath = Join-Path $libraryDir ($finalSlug + ".html")
    $launcherHtml = New-LauncherHtml -LibrarySlug $librarySlug -LibraryName $library.name -Entry $finalEntry
    [System.IO.File]::WriteAllText($launcherPath, $launcherHtml, [System.Text.UTF8Encoding]::new($false))
  }

  $sortedEntries = @($library.entries | Sort-Object slug)
  Write-Utf8Json -Path $library.manifestPath -Value $sortedEntries
}

$updatedSources = New-Object System.Collections.Generic.List[object]
foreach ($source in $sources) {
  $href = [string]$source.localHref
  if ($href -match "^\./([^/]+)/$") {
    $librarySlug = $Matches[1]
    if ($librarySlug -eq $recoveredSlug) {
      continue
    }
    if ($libraries.ContainsKey($librarySlug)) {
      $notePrefix = if ([string]$source.note -match "^\d+\s+") {
        ([string]$source.note -replace "^\d+\s+", "")
      } else {
        "local launchers"
      }
      $updatedSources.Add([pscustomobject]@{
        name = [string]$source.name
        url = [string]$source.url
        tag = [string]$source.tag
        localHref = [string]$source.localHref
        note = ("{0} {1}" -f $libraries[$librarySlug].entries.Count, $notePrefix)
      }) | Out-Null
      continue
    }
  }

  $updatedSources.Add($source) | Out-Null
}

Write-Utf8Json -Path $sourcesPath -Value ($updatedSources.ToArray())

$summary = [ordered]@{}
foreach ($librarySlug in ($distribution.Keys | Sort-Object)) {
  $summary[$librarySlug] = $distribution[$librarySlug].Count
}

Write-Output ($summary | ConvertTo-Json -Depth 4)
