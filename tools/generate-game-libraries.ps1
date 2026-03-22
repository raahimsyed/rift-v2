param(
  [string[]]$SelectedLibraries = @()
)

$SelectedLibraries = @($SelectedLibraries | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.ToLowerInvariant() })

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = Split-Path $PSScriptRoot -Parent
$gamesRoot = Join-Path $repoRoot "games"
$assetsJs = Join-Path $repoRoot "assets\js"

function Escape-Html([string]$Value) {
  return [System.Security.SecurityElement]::Escape([string]$Value)
}

function Encode-Path([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ""
  }

  return (($Path -split "/") | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join "/"
}

function Normalize-Slug([string]$Value) {
  $slug = [System.Uri]::UnescapeDataString([string]$Value).ToLowerInvariant()
  $slug = $slug -replace "[\\/]+", "-"
  $slug = $slug -replace "\s+", "-"
  $slug = $slug -replace "[^a-z0-9._-]", "-"
  $slug = $slug -replace "-{2,}", "-"
  return $slug.Trim("-")
}

function Format-Name([string]$Value) {
  $name = [System.Uri]::UnescapeDataString([string]$Value)
  $name = $name -replace "\.(html?|xml)$", ""
  $name = $name -replace "[-_]+", " "
  $name = $name -replace "\s{2,}", " "
  return $name.Trim()
}

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Read-JsonFile([string]$Path) {
  if (-not (Test-Path $Path)) {
    return $null
  }

  $raw = [System.IO.File]::ReadAllText($Path)
  if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) {
    $raw = $raw.Substring(1)
  }

  if ([string]::IsNullOrWhiteSpace($raw)) {
    return $null
  }

  return $raw | ConvertFrom-Json
}

function Build-SourceInfo([string]$Path, $Config, [string]$SourceBasePath) {
  $encodedPath = Encode-Path $Path
  $basePath = if ([string]::IsNullOrWhiteSpace($SourceBasePath)) {
    (Split-Path $Path -Parent) -replace "\\", "/"
  } else {
    $SourceBasePath -replace "\\", "/"
  }
  $basePath = $basePath.Trim("/")
  $encodedDir = Encode-Path $basePath

  if ($Config.Provider -eq "github") {
    if ($Config.LoadMode -eq "srcdoc") {
      $sourceUrl = "https://raw.githubusercontent.com/$($Config.Owner)/$($Config.Repo)/$($Config.Ref)/$encodedPath"
      $sourceBaseUrl = if ([string]::IsNullOrWhiteSpace($encodedDir)) {
        "https://raw.githubusercontent.com/$($Config.Owner)/$($Config.Repo)/$($Config.Ref)/"
      } else {
        "https://raw.githubusercontent.com/$($Config.Owner)/$($Config.Repo)/$($Config.Ref)/$encodedDir/"
      }
    } else {
      $sourceUrl = "https://rawcdn.githack.com/$($Config.Owner)/$($Config.Repo)/$($Config.Ref)/$encodedPath"
      $sourceBaseUrl = if ([string]::IsNullOrWhiteSpace($encodedDir)) {
        "https://rawcdn.githack.com/$($Config.Owner)/$($Config.Repo)/$($Config.Ref)/"
      } else {
        "https://rawcdn.githack.com/$($Config.Owner)/$($Config.Repo)/$($Config.Ref)/$encodedDir/"
      }
    }
  } elseif ($Config.Provider -eq "gitlab") {
    $sourceUrl = "https://gitlab.com/$($Config.Project)/-/raw/$($Config.Ref)/$encodedPath"
    $sourceBaseUrl = if ([string]::IsNullOrWhiteSpace($encodedDir)) {
      "https://gitlab.com/$($Config.Project)/-/raw/$($Config.Ref)/"
    } else {
      "https://gitlab.com/$($Config.Project)/-/raw/$($Config.Ref)/$encodedDir/"
    }
  } else {
    throw "Unsupported provider: $($Config.Provider)"
  }

  return [pscustomobject]@{
    sourceUrl = $sourceUrl
    sourceBaseUrl = $sourceBaseUrl
  }
}

function Get-RemoteTree([string]$RemoteUrl, [string[]]$RefsToTry) {
  $tempDir = Join-Path $env:TEMP ("rift-tree-" + [guid]::NewGuid().ToString("N"))

  try {
    git clone --depth 1 --filter=blob:none --no-checkout $RemoteUrl $tempDir | Out-Null
    foreach ($candidate in ($RefsToTry | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
      try {
        git -C $tempDir fetch --depth 1 --filter=blob:none origin $candidate | Out-Null
        $output = git -C $tempDir ls-tree -r --name-only FETCH_HEAD
        if ($LASTEXITCODE -eq 0 -and $output) {
          return @($output)
        }
      } catch {
        continue
      }
    }

    $output = git -C $tempDir ls-tree -r --name-only HEAD
    if ($LASTEXITCODE -eq 0 -and $output) {
      return @($output)
    }

    throw "Failed to read remote tree for $RemoteUrl"
  } finally {
    if (Test-Path $tempDir) {
      Remove-Item -Recurse -Force $tempDir
    }
  }
}

function Select-Paths($AllPaths, $Config) {
  $paths = @($AllPaths)
  $picked = @()

  if ($Config.Mode -eq "TopLevelIndex") {
    $picked = @($paths | Where-Object { $_ -match $Config.Pattern })
  }
  elseif ($Config.Mode -eq "DirectFiles") {
    $picked = @($paths | Where-Object { $_ -match $Config.Pattern })
  }
  elseif ($Config.Mode -eq "Mixed") {
    foreach ($pattern in $Config.Patterns) {
      $picked += @($paths | Where-Object { $_ -match $pattern })
    }
  }
  elseif ($Config.Mode -eq "RootAndTopLevelIndex") {
    $picked += @($paths | Where-Object { $_ -match $Config.RootPattern })
    $picked += @($paths | Where-Object { $_ -match $Config.IndexPattern })
  }
  else {
    throw "Unsupported mode: $($Config.Mode)"
  }

  if ($Config.ExtraPaths) {
    foreach ($extraPath in $Config.ExtraPaths) {
      if ($paths -contains $extraPath) {
        $picked += $extraPath
      }
    }
  }

  if ($Config.ExcludePatterns) {
    foreach ($pattern in $Config.ExcludePatterns) {
      $picked = @($picked | Where-Object { $_ -notmatch $pattern })
    }
  }

  return @($picked | Sort-Object -Unique)
}

function Get-EntryFromPath([string]$Path, $Config, [hashtable]$Seen) {
  $relative = $Path
  if ($Config.TrimPrefix) {
    if ($relative.StartsWith($Config.TrimPrefix)) {
      $relative = $relative.Substring($Config.TrimPrefix.Length)
    }
  }

  $relative = $relative.TrimStart("/")
  $slugBase = $relative

  if ($relative -match "/index\.(html?|xml)$") {
    $slugBase = ($relative -replace "/index\.(html?|xml)$", "")
  } else {
    $slugBase = ($relative -replace "\.(html?|xml)$", "")
  }

  $slug = Normalize-Slug $slugBase
  if ([string]::IsNullOrWhiteSpace($slug)) {
    return $null
  }

  $originalSlug = $slug
  $suffix = 2
  while ($Seen.ContainsKey($slug)) {
    $slug = "$originalSlug-$suffix"
    $suffix += 1
  }
  $Seen[$slug] = $true

  $nameSeed = Split-Path $slugBase -Leaf
  $name = Format-Name $nameSeed
  if ([string]::IsNullOrWhiteSpace($name)) {
    $name = $slug
  }

  $sourceInfo = Build-SourceInfo $Path $Config $null

  return [pscustomobject]@{
    slug = $slug
    name = $name
    path = $Path
    sourceUrl = $sourceInfo.sourceUrl
    sourceBaseUrl = $sourceInfo.sourceBaseUrl
    loadMode = $Config.LoadMode
  }
}

function Get-SyntheticEntry($Item, $Config, [hashtable]$Seen) {
  $slug = Normalize-Slug $Item.slug
  if ([string]::IsNullOrWhiteSpace($slug)) {
    return $null
  }

  $originalSlug = $slug
  $suffix = 2
  while ($Seen.ContainsKey($slug)) {
    $slug = "$originalSlug-$suffix"
    $suffix += 1
  }
  $Seen[$slug] = $true

  $name = if ([string]::IsNullOrWhiteSpace($Item.name)) { $slug } else { $Item.name }
  $loadMode = if ([string]::IsNullOrWhiteSpace($Item.loadMode)) { $Config.LoadMode } else { $Item.loadMode }
  $sourceInfo = Build-SourceInfo $Item.path $Config $Item.sourceBasePath

  return [pscustomobject]@{
    slug = $slug
    name = $name
    path = $Item.path
    sourceUrl = $sourceInfo.sourceUrl
    sourceBaseUrl = $sourceInfo.sourceBaseUrl
    loadMode = $loadMode
    sourceExtra = $Item.sourceExtra
  }
}

function Write-CatalogPage($LibraryDir, $Config) {
  $title = Escape-Html $Config.Title
  $meta = Escape-Html $Config.Meta
  $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Rift v2 / games / $title</title>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
  <link rel="stylesheet" href="../../assets/css/fonts.css">
  <link rel="stylesheet" href="../../assets/css/games.css">
</head>
<body data-library-name="$title" data-library-meta="$meta">
  <header class="topbar">
    <div class="topbar-left">rift /games /$title</div>
    <div class="topbar-center">
      <div class="topbar-search" aria-label="$title search">
        <i class="fa-solid fa-magnifying-glass" aria-hidden="true"></i>
        <input id="librarySearch" type="text" placeholder="Search $title games..." autocomplete="off" spellcheck="false" aria-label="Search $title games">
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
      <section class="collection" aria-label="$title library">
        <div class="section-title">$title library</div>
        <div class="subsection-title" id="libraryCount">loading...</div>
        <div class="empty" id="libraryEmpty">
          loading...
          <span class="empty-hint">if this stays, $title/games.json failed to load.</span>
        </div>
        <div class="grid" id="libraryGrid" hidden></div>
      </section>
    </section>
  </main>

  <script defer src="../../assets/js/library-catalog.js"></script>
</body>
</html>
"@
  Set-Content -Path (Join-Path $LibraryDir "index.html") -Value $html -Encoding utf8
}

function Write-LauncherPage($LibraryDir, $Config, $Entry) {
  $title = Escape-Html $Config.Title
  $gameName = Escape-Html $Entry.name
  $gameSlug = Escape-Html $Entry.slug
  $sourceUrl = Escape-Html $Entry.sourceUrl
  $sourceBaseUrl = Escape-Html $Entry.sourceBaseUrl
  $loadMode = Escape-Html $Entry.loadMode
  $sourceExtraAttr = ""
  if ($null -ne $Entry.sourceExtra) {
    $sourceExtraJson = $Entry.sourceExtra | ConvertTo-Json -Depth 10 -Compress
    $sourceExtraAttr = ' data-source-extra="' + (Escape-Html $sourceExtraJson) + '"'
  }

  $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Rift v2 / games / $title / $gameSlug</title>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
  <link rel="stylesheet" href="../../assets/css/fonts.css">
  <link rel="stylesheet" href="../../assets/css/game-frame.css">
</head>
<body data-library-slug="$($Config.Slug)" data-library-name="$title" data-game-slug="$gameSlug" data-game-name="$gameName" data-load-mode="$loadMode" data-source-url="$sourceUrl" data-source-base-url="$sourceBaseUrl"$sourceExtraAttr>
  <header class="topbar">
    <div class="title-block">
      <h1 class="title" id="gameTitle">$gameName</h1>
      <div class="sub" id="gameSub"></div>
    </div>
    <div class="actions">
      <div class="pill fps-pill" id="fpsCounter" aria-live="polite">
        -- fps
      </div>
      <button class="icon-btn" id="backToLibrary" type="button" aria-label="Back to $title library">
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

  Set-Content -Path (Join-Path $LibraryDir ($Entry.slug + ".html")) -Value $html -Encoding utf8
}

$libraries = @(
  @{
    Slug = "selenite"
    Title = "selenite"
    Meta = "selenite"
    SourceName = "selenite (old)"
    Provider = "github"
    Owner = "selenite-cc"
    Repo = "selenite-old"
    Ref = "main"
    Mode = "TopLevelIndex"
    Pattern = '^[^/]+/index\.html$'
    ExtraPaths = @(
      'adventure-capitalist/old/index.html',
      'ducklife1/flash/index.html',
      'ducklife1/unity/index.html',
      'ducklife2/flash/index.html',
      'ducklife2/unity/index.html',
      'ducklife3/flash/index.html',
      'ducklife3/unity/index.html',
      'ducklife4/flash/index.html',
      'ducklife4/unity/index.html',
      'pokemon/blue/index.html',
      'pokemon/crystal/index.html',
      'pokemon/emerald/index.html',
      'pokemon/firered/index.html',
      'pokemon/gold/index.html',
      'pokemon/leafgreen/index.html',
      'pokemon/red/index.html',
      'pokemon/ruby/index.html',
      'pokemon/sapphire/index.html',
      'pokemon/silver/index.html',
      'pokemon/yellow/index.html'
    )
    LoadMode = "url"
  },
  @{
    Slug = "elite-gamez"
    Title = "elite gamez"
    Meta = "elite"
    SourceName = "elite gamez games"
    Provider = "github"
    Owner = "elite-gamez"
    Repo = "Elite_gamez_games"
    Ref = "main"
    Mode = "DirectFiles"
    Pattern = '^[^/]+\.xml$'
    LoadMode = "srcdoc"
  },
  @{
    Slug = "fyinx"
    Title = "fyinx"
    Meta = "fyinx"
    SourceName = "fyinx (g)"
    Provider = "github"
    Owner = "aukak"
    Repo = "fyinx"
    Ref = "main"
    Mode = "Mixed"
    Patterns = @(
      '^g/[^/]+\.(html|htm)$',
      '^g/[^/]+/index\.(html|htm)$',
      '^g/[^/]+/[^/]+\.(html|htm)$'
    )
    TrimPrefix = "g/"
    LoadMode = "url"
  },
  @{
    Slug = "pokemon"
    Title = "pokemon"
    Meta = "pokemon"
    SourceName = "pokemon html games"
    Provider = "github"
    Owner = "AlexBoops"
    Repo = "HTML-Games"
    Ref = "main"
    Mode = "DirectFiles"
    Pattern = '^Pokemon HTML Games/[^/]+\.(html|htm)$'
    TrimPrefix = "Pokemon HTML Games/"
    ExtraPaths = @(
      'Angry Birds Halloween.html',
      'Angry Birds Rio.html',
      'Ant Art Tycoon.html',
      'Saul Goodman Run.html',
      'Scale the Depths.html',
      'Sonic Mania.html'
    )
    LoadMode = "url"
  },
  @{
    Slug = "ugs"
    Title = "ugs"
    Meta = "ugs"
    SourceName = "ugs assets"
    Provider = "github"
    Owner = "bubbls"
    Repo = "UGS-Assets"
    Ref = "main"
    Mode = "TopLevelIndex"
    Pattern = '^[^/]+/index\.html$'
    ExtraPaths = @(
      'adventure-capitalist/old/index.html',
      'aviamaster/FUN.html',
      'banana poker/game.html',
      'blockpost/clblockpost.html',
      'duck life 6/game.html',
      'going balls/play.html',
      'google-gnome/gnomes18.html',
      'gravity/fcgravity.html',
      'grindcraft/play.html',
      'onebit/onebit/index.html',
      'quake/quake.html',
      'resizer/game.html',
      'retro bowl/new.html',
      'strands/strands-game.html',
      'super-onion-boy-2/index-x.html',
      'table tennis world tour/game.html',
      'tag-cm/play.html',
      'tempoverdose/tempoverdose.html',
      'todee and todpee/play.html',
      'ztype/play.html'
    )
    LoadMode = "url"
  },
  @{
    Slug = "radon"
    Title = "radon"
    Meta = "radon"
    SourceName = "radon games assets"
    Provider = "github"
    Owner = "Radon-Games"
    Repo = "Radon-Games-Assets"
    Ref = "main"
    Mode = "TopLevelIndex"
    Pattern = '^html/[^/]+/index\.html$'
    TrimPrefix = "html/"
    ExtraPaths = @(
      'html/celeste/celeste.html',
      'html/muffin-knight/fullscreen.html',
      'html/radius-raid/min.html',
      'html/spaceinvaders/indexOpt.html',
      'unity/superhot/index.html'
    )
    LoadMode = "url"
  },
  @{
    Slug = "3kh0"
    Title = "3kh0"
    Meta = "3kh0"
    SourceName = "3kh0 assets (gitlab)"
    Provider = "gitlab"
    Project = "3kh0/3kh0-assets"
    Ref = "main"
    Mode = "TopLevelIndex"
    Pattern = '^[^/]+/index\.html$'
    ExtraPaths = @(
      'backrooms2d/backrooms2d.html',
      'balldodge/balldodge.html',
      'bonkio/bonkio.html',
      'checkers/checkers.html',
      'chess/chess.html',
      'dodge/dodge.html',
      'doom/doom.html',
      'dumbwaystodie/dumbwaystodie.html',
      'fantasy-dash/Fantasy Dash.html',
      'flappy plane/Flappy Plane.html',
      'geodashlite/geodashlite.html',
      'goodnight-meowmie/itchwrapper.html',
      'hellscaper/Hellscaper WebGL 4-19-23/index.html',
      'idledice/Idle Dice.html',
      'iron dash/Iron Dash.html',
      'kirkaio/kirka.html'
    )
    LoadMode = "srcdoc"
  },
  @{
    Slug = "ccported"
    Title = "ccported"
    Meta = "ccported"
    SourceName = "ccported games"
    Provider = "github"
    Owner = "ccported"
    Repo = "games"
    Ref = "main"
    Mode = "TopLevelIndex"
    Pattern = '^game_[^/]+/index\.html$'
    LoadMode = "url"
  },
  @{
    Slug = "gn-math"
    Title = "gn-math"
    Meta = "gn-math"
    SourceName = "gn-math assets"
    Provider = "github"
    Owner = "gn-math"
    Repo = "assets"
    Ref = "main"
    Mode = "Mixed"
    Patterns = @(
      '^[^/]+/index\.html$',
      '^[^/]+/[^/]+\.(html|htm)$'
    )
    SyntheticEntries = @(
      @{
        slug = "174"
        name = "worldbox"
        path = "174/worldbox.swf"
        loadMode = "ruffle"
      },
      @{
        slug = "175"
        name = "run"
        path = "175/Run.swf"
        loadMode = "ruffle"
      },
      @{
        slug = "176"
        name = "run2"
        path = "176/Run2.swf"
        loadMode = "ruffle"
      },
      @{
        slug = "178"
        name = "178"
        path = "178/178.swf"
        loadMode = "ruffle"
      },
      @{
        slug = "184"
        name = "184"
        path = "184/script.js"
        loadMode = "script"
      },
      @{
        slug = "186"
        name = "186"
        path = "186/Build/v111.loader.js"
        sourceBasePath = "186/"
        loadMode = "unity"
        sourceExtra = @{
          buildBaseUrl = "https://rawcdn.githack.com/gn-math/assets/main/186/Build/"
          dataUrl = "https://rawcdn.githack.com/gn-math/assets/main/186/Build/6697b6deba8b617c67b69c55dcd07cb1.data.unityweb"
          frameworkUrl = "https://rawcdn.githack.com/gn-math/assets/main/186/Build/0be3c3ee7115b26e1ae28e643afdf1f2.js.unityweb"
          codeUrl = "https://rawcdn.githack.com/gn-math/assets/main/186/Build/b3397c29f6878557c1c614cbf9e196ea.wasm.unityweb"
          streamingAssetsUrl = "https://rawcdn.githack.com/gn-math/assets/main/186/StreamingAssets/"
          companyName = "gn-math"
          productName = "186"
          productVersion = "1.0"
        }
      },
      @{
        slug = "187"
        name = "187"
        path = "187/187.swf"
        loadMode = "ruffle"
      },
      @{
        slug = "197"
        name = "197"
        path = "197/face.js"
        loadMode = "face"
      }
    )
    LoadMode = "url"
  },
  @{
    Slug = "seraph"
    Title = "seraph"
    Meta = "seraph"
    SourceName = "seraph (games)"
    Provider = "github"
    Owner = "a456pur"
    Repo = "seraph"
    Ref = "main"
    Mode = "TopLevelIndex"
    Pattern = '^games/[^/]+/index\.html$'
    TrimPrefix = "games/"
    LoadMode = "url"
  },
  @{
    Slug = "unblockedgames"
    Title = "unblockedgames"
    Meta = "unblockedgames"
    SourceName = "unblockedgames (games)"
    Provider = "github"
    Owner = "Fluffygirlwoman"
    Repo = "UnblockedGames"
    Ref = "main"
    Mode = "DirectFiles"
    Pattern = '^Games/[^/]+\.(html|htm)$'
    TrimPrefix = "Games/"
    LoadMode = "url"
  },
  @{
    Slug = "artclass"
    Title = "artclass"
    Meta = "artclass"
    SourceName = "artclass v2 (games)"
    Provider = "github"
    Owner = "proudparrot2"
    Repo = "artclass-v2"
    Ref = "main"
    Mode = "DirectFiles"
    Pattern = '^games/[^/]+\.(html|htm)$'
    TrimPrefix = "games/"
    LoadMode = "url"
  },
  @{
    Slug = "t9lat22"
    Title = "t9lat22"
    Meta = "t9lat22"
    SourceName = "t9lat22.github.io"
    Provider = "github"
    Owner = "t9lat22"
    Repo = "t9lat22.github.io"
    Ref = "master"
    Mode = "RootAndTopLevelIndex"
    RootPattern = '^[^/]+\.(html|htm)$'
    IndexPattern = '^[^/]+/index\.(html|htm)$'
    TrimPrefix = "Games/"
    ExtraPaths = @(
      'Games/1v1lol-main/index.html',
      'Games/cubeshot-io-main/index.html',
      'Games/drive-mad-main/index.html'
    )
    ExcludePatterns = @(
      '(^|/)404\.(html|htm)$',
      '^admin\.(html|htm)$',
      '^ads?\.(html|htm)$',
      '^search\.(html|htm)$',
      '^appmaker\.(html|htm)$',
      '^apposes?\.(html|htm)$',
      '^aiwarn\.(html|htm)$',
      '^public/index\.(html|htm)$',
      '^static/index\.(html|htm)$',
      '^test2?/index\.(html|htm)$',
      '^new/index\.(html|htm)$',
      '^stuff/index\.(html|htm)$'
    )
    LoadMode = "url"
  },
  @{
    Slug = "noah"
    Title = "noah"
    Meta = "noah"
    SourceName = "noahs calculus tutor (games)"
    Provider = "github"
    Owner = "NoahsAmazingTutoringHelp"
    Repo = "Noahs-Calculus-Tutor"
    Ref = "master"
    Mode = "DirectFiles"
    Pattern = '^games/[^/]+\.(html|htm)$'
    TrimPrefix = "games/"
    LoadMode = "url"
  },
  @{
    Slug = "crunchingmath"
    Title = "crunchingmath"
    Meta = "crunchingmath"
    SourceName = "crunchingmath (games)"
    Provider = "github"
    Owner = "UGBONTOP"
    Repo = "crunchingmath"
    Ref = "main"
    Mode = "Mixed"
    Patterns = @(
      '^testsite/games/[^/]+\.(html|htm)$',
      '^testsite/games/[^/]+/index\.html$'
    )
    TrimPrefix = "testsite/games/"
    LoadMode = "url"
  }
)

$sourcesPath = Join-Path $gamesRoot "sources.json"
$sources = Get-Content -Raw $sourcesPath | ConvertFrom-Json

if ($SelectedLibraries.Count -gt 0) {
  $libraries = @($libraries | Where-Object { $SelectedLibraries -contains $_.Slug })
}

foreach ($library in $libraries) {
  Write-Output ("Generating " + $library.Slug + "...")
  $paths = if ($library.Provider -eq "github") {
    Get-RemoteTree ("https://github.com/$($library.Owner)/$($library.Repo).git") @($library.Ref, "main", "master")
  } else {
    Get-RemoteTree ("https://gitlab.com/$($library.Project).git") @($library.Ref, "main", "master")
  }

  $picked = Select-Paths $paths $library
  $seen = @{}
  $entries = foreach ($path in $picked) {
    Get-EntryFromPath $path $library $seen
  }
  if ($library.SyntheticEntries) {
    foreach ($item in $library.SyntheticEntries) {
      $entries += Get-SyntheticEntry $item $library $seen
    }
  }
  $entries = @($entries | Where-Object { $_ } | Sort-Object slug)

  $libraryDir = Join-Path $gamesRoot $library.Slug
  Ensure-Dir $libraryDir

  $existingManifestPath = Join-Path $libraryDir "games.json"
  $existingEntries = @(Read-JsonFile $existingManifestPath)
  $existingBySlug = @{}
  foreach ($existing in $existingEntries) {
    if ($existing.slug) {
      $existingBySlug[[string]$existing.slug] = $existing
    }
  }

  foreach ($entry in $entries) {
    $slug = [string]$entry.slug
    if (-not $existingBySlug.ContainsKey($slug)) {
      continue
    }

    $existing = $existingBySlug[$slug]
    if ($existing.PSObject.Properties["thumbnailUrl"]) {
      $entry | Add-Member -NotePropertyName thumbnailUrl -NotePropertyValue ([string]$existing.thumbnailUrl) -Force
    }
  }

  $entries | Select-Object slug, name, sourceUrl, sourceBaseUrl, loadMode, sourceExtra, thumbnailUrl | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $libraryDir "games.json") -Encoding utf8
  Write-CatalogPage $libraryDir $library

  foreach ($entry in $entries) {
    Write-LauncherPage $libraryDir $library $entry
  }

  $source = $sources | Where-Object { $_.name -eq $library.SourceName } | Select-Object -First 1
  if ($source) {
    $source | Add-Member -NotePropertyName localHref -NotePropertyValue ("./" + $library.Slug + "/") -Force
    $source | Add-Member -NotePropertyName note -NotePropertyValue ("{0} local launchers" -f $entries.Count) -Force
  }

  Write-Output ("Generated {0}: {1}" -f $library.Slug, $entries.Count)
}

$sources | ConvertTo-Json -Depth 5 | Set-Content -Path $sourcesPath -Encoding utf8
