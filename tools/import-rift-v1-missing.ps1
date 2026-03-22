param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$v1ManifestPath = "C:\Users\Raahim\rift\data\truffled-root-manifest.json"
$v1PublicRoot = "C:\Users\Raahim\rift\public"
$gamesRoot = Join-Path $repoRoot "games"
$librarySlug = "rift-v1-missing"
$libraryDir = Join-Path $gamesRoot $librarySlug
$sourcesPath = Join-Path $gamesRoot "sources.json"

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Normalize-Key([string]$Value) {
  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) { return "" }
  $text = $text.Trim().ToLowerInvariant()
  $text = $text -replace "[^a-z0-9]+", " "
  $text = $text -replace "\s{2,}", " "
  return $text.Trim()
}

function Format-Name([string]$Stem) {
  $parts = ([string]$Stem) -replace "[-_]+", " "
  $parts = $parts -replace "\s{2,}", " "
  return $parts.Trim()
}

function Escape-Html([string]$Value) {
  return [System.Security.SecurityElement]::Escape([string]$Value)
}

function Get-PrettyName([string]$FileName, [string]$Fallback) {
  $filePath = Join-Path $v1PublicRoot $FileName
  if (-not (Test-Path $filePath)) {
    return $Fallback
  }

  try {
    $html = Get-Content -Raw $filePath
  } catch {
    return $Fallback
  }

  $titleMatch = [regex]::Match($html, "<title>\s*(.*?)\s*</title>", "IgnoreCase, Singleline")
  if ($titleMatch.Success) {
    $title = [System.Net.WebUtility]::HtmlDecode($titleMatch.Groups[1].Value).Trim()
    if (-not [string]::IsNullOrWhiteSpace($title)) {
      $title = $title -replace "^(Unity WebGL Player|Unity Web Player|gn-math.github.io|webport.ing|Truffled)\s*\|\s*", ""
      $title = $title -replace "\s*[|:-]\s*(Rift|Truffled.*)$", ""
      $title = $title -replace "\s{2,}", " "
      $title = $title.Trim()
      $badTitles = @(
        "404",
        "truffled - 404",
        "emscripten-generated code",
        "yt game wrapper webgl template",
        "wrapper",
        "home | schoology",
        "game :d"
      )
      if (
        -not [string]::IsNullOrWhiteSpace($title) -and
        -not ($badTitles -contains $title.ToLowerInvariant())
      ) {
        return $title
      }
    }
  }

  $ogMatch = [regex]::Match($html, 'property=["'']og:title["'']\s+content=["'']([^"'']+)["'']', "IgnoreCase")
  if ($ogMatch.Success) {
    $title = [System.Net.WebUtility]::HtmlDecode($ogMatch.Groups[1].Value).Trim()
    if (-not [string]::IsNullOrWhiteSpace($title)) {
      return $title
    }
  }

  return $Fallback
}

$manifest = Get-Content -Raw $v1ManifestPath | ConvertFrom-Json
$sourceMap = $manifest.map
if (-not $sourceMap) {
  throw "Missing manifest map in $v1ManifestPath"
}

$existingSlugs = New-Object 'System.Collections.Generic.HashSet[string]'
$existingNames = New-Object 'System.Collections.Generic.HashSet[string]'

Get-ChildItem $gamesRoot -Directory | ForEach-Object {
  if ($_.Name -eq $librarySlug) {
    return
  }

  $gamesJsonPath = Join-Path $_.FullName "games.json"
  if (-not (Test-Path $gamesJsonPath)) {
    return
  }

  try {
    $entries = Get-Content -Raw $gamesJsonPath | ConvertFrom-Json
  } catch {
    return
  }

  foreach ($entry in $entries) {
    if ($entry.slug) {
      [void]$existingSlugs.Add((Normalize-Key $entry.slug))
    }
    if ($entry.name) {
      [void]$existingNames.Add((Normalize-Key $entry.name))
    }
  }
}

$blocked = @(
  "404",
  "account",
  "apps",
  "browser",
  "chat",
  "cloud",
  "credits",
  "embed",
  "index",
  "config",
  "code-citations",
  "favicon"
)

$missing = New-Object System.Collections.Generic.List[object]

foreach ($property in $sourceMap.PSObject.Properties) {
  $target = [string]$property.Name
  $file = [string]$property.Value

  if ([string]::IsNullOrWhiteSpace($file) -or -not $file.EndsWith(".html")) {
    continue
  }

  $stem = [System.IO.Path]::GetFileNameWithoutExtension($file).ToLowerInvariant()
  if ($blocked -contains $stem) {
    continue
  }

  if ($target.Contains("{prefix}")) {
    continue
  }

  $prettyFallback = Format-Name $stem
  $normalizedStem = Normalize-Key $stem
  $normalizedName = Normalize-Key $prettyFallback

  if ($existingSlugs.Contains($normalizedStem) -or $existingNames.Contains($normalizedName)) {
    continue
  }

  $name = Get-PrettyName -FileName $file -Fallback $prettyFallback
  $url = "https://truffled.lol/" + $target.TrimStart("/")
  $missing.Add([pscustomobject]@{
    slug = $stem
    name = $name
    sourceUrl = $url
    sourceBaseUrl = ""
    loadMode = "url"
  }) | Out-Null
}

$missing = @($missing | Sort-Object slug)

Ensure-Dir $libraryDir

$gamesJson = $missing | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText((Join-Path $libraryDir "games.json"), $gamesJson, [System.Text.UTF8Encoding]::new($false))

$catalogHtml = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Rift v2 / games / rift v1 missing</title>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
  <link rel="stylesheet" href="../../assets/css/fonts.css">
  <link rel="stylesheet" href="../../assets/css/games.css">
</head>
<body data-library-name="rift v1 missing" data-library-meta="recovered from rift v1">
  <header class="topbar">
    <div class="topbar-left">rift /games /rift v1 missing</div>
    <div class="topbar-center">
      <div class="topbar-search" aria-label="rift v1 missing search">
        <i class="fa-solid fa-magnifying-glass" aria-hidden="true"></i>
        <input id="librarySearch" type="text" placeholder="Search recovered Rift v1 games..." autocomplete="off" spellcheck="false" aria-label="Search recovered Rift v1 games">
      </div>
    </div>
    <div class="topbar-right">
      <button class="icon-btn" id="backToGames" type="button" aria-label="Back to games">
        <i class="fa-solid fa-arrow-left" aria-hidden="true"></i>
      </button>
    </div>
  </header>

  <main class="wrap">
    <section class="panel">
      <section class="collection" aria-label="rift v1 missing library">
        <div class="section-title">rift v1 missing</div>
        <div class="subsection-title" id="libraryCount">loading...</div>
        <div class="empty" id="libraryEmpty">
          loading...
          <span class="empty-hint">if this stays, rift-v1-missing/games.json failed to load.</span>
        </div>
        <div class="grid" id="libraryGrid" hidden></div>
      </section>
    </section>
  </main>

  <script defer src="../../assets/js/library-catalog.js"></script>
</body>
</html>
"@
[System.IO.File]::WriteAllText((Join-Path $libraryDir "index.html"), $catalogHtml, [System.Text.UTF8Encoding]::new($false))

foreach ($entry in $missing) {
  $title = Escape-Html ("Rift v2 / games / rift v1 missing / " + $entry.slug)
  $gameName = Escape-Html $entry.name
  $gameSlug = Escape-Html $entry.slug
  $sourceUrl = Escape-Html $entry.sourceUrl

  $launcher = @"
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
<body data-library-slug="$librarySlug" data-library-name="rift v1 missing" data-game-slug="$gameSlug" data-game-name="$gameName" data-load-mode="url" data-source-url="$sourceUrl" data-source-base-url="">
  <header class="topbar">
    <div class="title-block">
      <h1 class="title" id="gameTitle">$gameName</h1>
      <div class="sub" id="gameSub"></div>
    </div>
    <div class="actions">
      <div class="pill fps-pill" id="fpsCounter" aria-live="polite">
        -- fps
      </div>
      <button class="icon-btn" id="backToLibrary" type="button" aria-label="Back to rift v1 missing library">
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

  [System.IO.File]::WriteAllText((Join-Path $libraryDir ($entry.slug + ".html")), $launcher, [System.Text.UTF8Encoding]::new($false))
}

$sources = Get-Content -Raw $sourcesPath | ConvertFrom-Json
$filteredSources = @($sources | Where-Object { $_.name -ne "rift v1 missing" })
$filteredSources += [pscustomobject]@{
  name = "rift v1 missing"
  url = "https://truffled.lol/"
  tag = "recovered"
  localHref = "./$librarySlug/"
  note = ("{0} recovered launchers" -f $missing.Count)
}
$sourcesJson = $filteredSources | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($sourcesPath, $sourcesJson, [System.Text.UTF8Encoding]::new($false))

Write-Output ("rift_v1_missing_count=" + $missing.Count)
