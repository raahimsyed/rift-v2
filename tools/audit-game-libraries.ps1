$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$auditRoot = "C:\Users\Raahim\AppData\Local\Temp\rift-library-mirrors"

$repos = @(
  @{ slug = "selenite"; url = "https://github.com/selenite-cc/selenite-old.git" },
  @{ slug = "elite-gamez"; url = "https://github.com/elite-gamez/Elite_gamez_games.git" },
  @{ slug = "fyinx"; url = "https://github.com/aukak/fyinx.git" },
  @{ slug = "pokemon"; url = "https://github.com/AlexBoops/HTML-Games.git" },
  @{ slug = "ugs"; url = "https://github.com/bubbls/UGS-Assets.git" },
  @{ slug = "radon"; url = "https://github.com/Radon-Games/Radon-Games-Assets.git" },
  @{ slug = "3kh0"; url = "https://gitlab.com/3kh0/3kh0-assets.git" },
  @{ slug = "ccported"; url = "https://github.com/ccported/games.git" },
  @{ slug = "gn-math"; url = "https://github.com/gn-math/assets.git" },
  @{ slug = "seraph"; url = "https://github.com/a456pur/seraph.git" },
  @{ slug = "unblockedgames"; url = "https://github.com/Fluffygirlwoman/UnblockedGames.git" },
  @{ slug = "artclass"; url = "https://github.com/proudparrot2/artclass-v2.git" },
  @{ slug = "t9lat22"; url = "https://github.com/t9lat22/t9lat22.github.io.git" },
  @{ slug = "noah"; url = "https://github.com/NoahsAmazingTutoringHelp/Noahs-Calculus-Tutor.git" },
  @{ slug = "crunchingmath"; url = "https://github.com/UGBONTOP/crunchingmath.git" }
)

if (-not (Test-Path $auditRoot)) {
  New-Item -ItemType Directory -Path $auditRoot | Out-Null
}

foreach ($repo in $repos) {
  $dest = Join-Path $auditRoot ($repo.slug + ".git")
  if (Test-Path $dest) {
    Write-Host ("UPDATING " + $repo.slug)
    git --git-dir="$dest" remote update --prune
    if ($LASTEXITCODE -eq 0) {
      continue
    }

    Write-Warning ("Mirror update failed for " + $repo.slug + ", recloning")
    Remove-Item -Recurse -Force $dest
  }
  Write-Host ("CLONING " + $repo.slug)
  git clone --mirror $repo.url $dest
  if ($LASTEXITCODE -ne 0) {
    throw ("Clone failed: " + $repo.slug)
  }
}

Write-Host "DONE"
