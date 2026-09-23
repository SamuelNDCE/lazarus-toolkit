# Lazarus Toolkit

> **What this file is.** `PROJECT.md` holds the **operational rules for this repo**: the things that
> decide what you are allowed to do right now. How to deploy and what gates it, what to run before
> claiming something works, when to push and when not to, which env vars must exist, what a term
> here actually means, and where things live. It is loaded automatically at the start of every
> session by `~/.claude/helpers/project-doc-hook.cjs`, so these rules apply whether or not anyone
> thought to open the file.
>
> **The test for whether a fact belongs here: would it change what I am allowed to do right now?**
> If yes, it is operational and it lives here, next to the code it governs, so a fresh clone cannot
> lose it. If it is context, history or reasoning, it belongs in the vault note instead.
> **Nothing is duplicated between the two**, because two copies disagree eventually with nothing to
> say which is current.

A Windows repair USB stick (`Lazarus.hta` launcher, `Start.bat`) plus **Health Report and Repair**
(`Tools\`), which also installs per-user onto a PC. Two delivery paths that must not be confused:
the **stick** (nothing is installed on the machine being fixed) and the **web install** (the
one-line `irm ... | iex` at the root `install.ps1`). Background and history:
the maintainer's private vault note `lazarus-usb-toolkit`.

## Pushing

- Default branch is **`main`**, and it is also what the world sees: `install.ps1` is fetched live
  from `raw.githubusercontent.com/.../main/install.ps1`. **A push to `main` changes what every
  future one-liner runs, immediately.** There is no staging.
- **Never push unless the maintainer asks.** The Stop hook checkpoints tracked files locally every turn
  and does not push. Verify a push landed with `git branch -r --contains <sha>`.

## Deploy

There is no build step. Deploy is a push to `main`. Before one:
1. `powershell -NoProfile -ExecutionPolicy Bypass -File Tests\Run-Checks.ps1` (see Verify).
2. If `install.ps1` changed, the maintainer runs it locally first and says it is good.
   Local trial, closest to the real path: `Get-Content -Raw .\install.ps1 | iex`.

## Verify

- `Tests\Run-Checks.ps1` runs every static check. Exits non-zero with a count on failure.
  Snapshot 2026-09-23: everything passes except "the screenshot is current" (stale
  `Docs\images\launcher.png`), which predates and is unrelated to installer work.
- `node Docs\validate.js "D:\"` and `node Docs\orphans.js` check the launcher against the stick.
- The web installer cannot be tested against the real download without pushing. Test a **copy**
  of it with `$zipUrl` pointed at a `git archive` zip via a `file://` URL, with a stub for the UAC
  launch. Back up `HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\HealthReportAndRepair`
  first (`reg export`), because `Uninstall.ps1` deletes that key and a real install on the test machine uses it.
- The elevated (UAC) launch cannot be exercised by an agent. Say so rather than claiming it works.

## Environment

None to set. The scripts read only standard Windows variables (`LOCALAPPDATA`, `APPDATA`, `TEMP`,
`WT_SESSION`, and similar). No secrets, no API keys.

## Hard rules

- **The USB stick must not change behaviour.** `Start.bat` to `Lazarus.hta` never touches the root
  `install.ps1`. Web-install-only behaviour (run then offer to remove) lives in the root
  `install.ps1` only. `Tools\Install.ps1` and `Tools\Install.bat` still just install.
- **Never call `exit` in the root `install.ps1`** except the guarded one at the bottom. Under
  `irm | iex` it kills the person's whole terminal. Use `return`.
- **The report window opens in Windows Terminal, never a bare elevated `powershell.exe`** (that
  is the old navy console host, hard to read). `wt.exe` returns in about 0.1s while its window
  lives on, so completion is tracked by `done.txt` and a heartbeat `alive.txt` that the window
  writes into a temp folder (measured 2026-09-23). The wrapper is an inline `-EncodedCommand`, not
  a script file, so nothing on disk can be swapped before it runs elevated. Without `wt.exe` it
  falls back to `powershell.exe`.
- **Anything that can block shows live progress and has a timeout**, and the install must never sit
  silent. Keep animated lines under 78 columns and ASCII only (fetched over the web, any code page).
- **`Tools\` contains no network calls** except the optional Windows Update repair. The one
  downloader is the root `install.ps1`. Not enforced by a test: it is checked by the
  `Select-String` one-liner in README ("Your data never leaves your machine"), which must return
  nothing. Run it after touching `Tools\`. (`Tests\check-privacy.ps1` is a different check: it
  fails on people, machine names and personal paths about to be published.)
- Install payload is an explicit file list, never a wildcard, so a saved report (serial number,
  machine name) never travels to the next PC. Uninstall never deletes saved reports by default.
- No em dashes in anything written here or shown to users.

## Where things are

- `install.ps1` web installer. `Tools\Install.ps1` / `Uninstall.ps1` the real installer.
- `Tools\Health-Report.ps1`, `Repair-Health.ps1`, `Common.ps1` the tool itself.
- `Tests\` static checks. `Docs\` launcher validators.
