# Lazarus Toolkit

A USB repair stick for secondhand and ex-corporate Windows machines. It surveys a PC using data
Windows already has, tells you plainly what is wrong with it, and then repairs what it found using
Windows' own tools. Nothing is installed on the machine being fixed.

Built for a real job: getting donated ex-corporate laptops fit to hand to a child at a coding club,
and repairing client machines. Every guard in it exists because something went wrong on an actual
computer.

---

## Quick start

**Double-click `Start.bat`.** That opens the launcher, which is the menu everything is run from. It
is the only thing you need to remember.

```powershell
git clone https://github.com/SamuelNDCE/lazarus-toolkit.git
cd lazarus-toolkit
.\Start.bat
```

`Start.bat` opens `Lazarus.hta`, the graphical launcher. From there you pick a tool and it runs.
**Health Report and Repair works immediately with nothing downloaded.**

### It is a collection of tools, not one program

The launcher is a front door, not a wrapper. **Everything under `Tools\` is a self-contained
program you can run directly, on its own, without the launcher and without the rest of the
toolkit.** Double-click it, or call it from a terminal, and it works.

That is worth knowing because the useful thing is often one tool, not the whole stick:

```powershell
.\Tools\HealthReport\Health-Report.bat        # survey and repair this PC
.\Tools\HealthReport\Collect-ToolLogs.ps1     # gather every repair log on the machine
.\Tools\HealthReport\Clear-Reports.ps1        # clear what has piled up on the stick
```

Copy `Tools\HealthReport\` onto a share, a different stick, or straight onto a client machine, and
it runs there unchanged. It has no installer to depend on, no registry keys it needs, and no path
baked into it. `Install.bat` exists to make it convenient, never to make it work.

The launcher additionally lists around 40 third-party utilities, which are **not** bundled here
(see Licensing), so a fresh clone shows those as missing until you add them. They are ordinary
portable programs too, and drop into `Tools\<Name>\` alongside this one.

Prefer to skip the launcher and go straight to the main tool:

```powershell
.\HealthReport\Health-Report.bat
```

| I want to | Run |
|---|---|
| **Open the launcher (start here)** | **`Start.bat`** |
| Run the main tool | `Tools\HealthReport\Health-Report.bat` |
| **Install the main tool on this PC** | **`Tools\HealthReport\Install.bat`** |
| Survey a machine and save nothing | `Health-Report.ps1 -NoSave` |
| Survey it with no keypresses at all | `Health-Report.ps1 -Unattended` |
| Go straight to repairs | `Repair-Health.ps1` |
| Collect the logs other tools left behind | `Collect-ToolLogs.ps1` |
| Delete the saved reports | `Clear-Reports.ps1 -Confirm` |
| Check the toolkit itself is sound | `Tests\Run-Checks.ps1` |
| Check a USB stick before unplugging | `Tests\Test-StickReady.ps1 -Drive D:` |

**Requirements:** Windows 10 or 11, Windows PowerShell 5.1 (built in). Administrator for SMART data,
BitLocker, battery capacity, driver installs, and any repair. The tool asks for it itself.

---

## Installing just the health report

The stick is the point of this project, and it stays the point: on a machine you are fixing, you
plug in, you run, you unplug, and nothing is left behind.

Your own machine is the other case. The bench PC, the laptop you carry to a job. There you want the
tool on the Start menu and in the terminal, not four folders down on a stick that is in a drawer.

```powershell
.\HealthReport\Install.bat
```

Or on a machine with nothing on it yet, one line:

```powershell
irm https://raw.githubusercontent.com/SamuelNDCE/lazarus-toolkit/main/install.ps1 | iex
```

Either way you get the same thing:

| | |
|---|---|
| **Installed to** | `%LOCALAPPDATA%\Programs\Health Report and Repair` |
| **Start menu** | search for "Health Report" |
| **Desktop** | an icon, same as the Start menu one |
| **Terminal** | type `health-report` anywhere |
| **Uninstall** | Settings > Apps > Installed apps, or `Uninstall.ps1` |

**Installing needs no administrator, and that is deliberate rather than an oversight.** The install
goes into your own profile, so elevating would install it into the *administrator's* profile
instead: the shortcuts, the PATH entry and the Add/Remove Programs entry would all land on an
account nobody is using, and you would see a successful install and then find nothing on your Start
menu. The **tool** still elevates itself every time it runs. Two different permissions.

Both shortcuts carry the run-as-administrator flag, so the UAC prompt is the first thing that
happens rather than a black window flashing up and vanishing while the script relaunches itself.
That flag also matters under AppLocker: an unelevated administrator holds a filtered token where
the Administrators SID is deny-only, so a rule granting Administrators does not match and a script
on removable media is killed before it can run a single line. A `.lnk` is not an executable, so it
is never evaluated, and the elevation happens first.

Before it finishes, the installer checks the machine rather than its own return codes: every file
present, both shortcuts created, the flag actually set in the shortcut header, and the copied
`Health-Report.ps1` parses. "Copy-Item did not throw" and "the file is there and it is valid" are
different claims.

It records everything it wrote in `installed.json`, and the uninstaller removes exactly that.
**Saved reports are never deleted by an uninstall**: they are moved to `Documents\Lazarus Reports`
and the new location is printed, because uninstalling the tool is not a statement about the
records. `-RemoveReports` deletes them, and you have to ask for it separately.

```powershell
.\Install.ps1 -WhatIfOnly      # say what it would do, touch nothing
.\Install.ps1 -NoPath          # skip the terminal command
.\Uninstall.ps1                # dry run, shows what would go
.\Uninstall.ps1 -Confirm       # do it
```

---

## The tools

### 1. Health Report and Repair

**What it does.** Reads everything Windows already knows about the machine and turns it into a
verdict: *ready to hand over*, *usable with notes*, or *not ready*.

**How it works.** Every check runs on a background thread with its own timeout and a live spinner,
so a slow call shows a climbing counter rather than a frozen screen. If a check does not answer in
time it says so and the run continues, and the report says which answer is missing. It never sends
anything anywhere.

#### It asks what you want first

The first screen is a chooser, the same arrow-key picker the repair menu uses. Up and down to move,
Enter to switch a row on or off, move to CONTINUE and press Enter.

**Press Enter and you get exactly what this tool has always done:** every section, and a saved
report. Everything is ticked by default. The chooser exists for the three jobs it could not do
before.

*"Just tell me what this machine is."* Untick everything except Machine. You get the make, model
and serial in about two seconds instead of eleven sections.

*"Do not write anything down."* Untick the last row, **SAVE A REPORT FILE**. Everything appears on
screen and nothing touches the disk. On a machine you do not own, a saved report is that person's
serial number and software inventory, and it then travels on your stick. Sometimes the honest thing
is to look, say it out loud, and leave nothing behind.

*"Skip the slow ones."* The update history and the program list are the two slowest checks here.
Untick them and the run is a fraction of the time.

Whatever you leave out is **named in the report** under "not included in this report", because a
file that silently omits three sections is indistinguishable from a run where those checks found
nothing, and that ambiguity is the one thing a handover record must not have.

From the command line, with no keypress at all:

```powershell
.\Health-Report.ps1 -Only 'M,A,B'   # only these sections
.\Health-Report.ps1 -Skip 'U,P'     # everything except these
.\Health-Report.ps1 -NoSave         # show it, write nothing
.\Health-Report.ps1 -Unattended     # all sections, save, no keypresses
```

| Key | Section | What you learn |
|---|---|---|
| `M` | Machine | Make, model, serial, BIOS version and age, CPU, GPU, motherboard |
| `A` | Windows activation | Licensed or not, and by which channel |
| `B` | Battery | Design vs full-charge capacity, wear percentage, cycle count |
| `D` | Storage | SMART data, power-on hours, reallocated sectors, SSD write life, free space |
| `R` | Memory | Sticks installed, speed, slots used |
| `V` | Drivers | Broken devices **ranked by severity**, generic-vs-vendor drivers, driver ages |
| `S` | Security | Defender, firewall, BitLocker, registered antivirus, Absolute/Computrace |
| `T` | System state | Restore points, uptime |
| `P` | Installed programs | Full program list, cross-checked against the registry |
| `U` | Windows Update | Recent installs and failures |
| `E` | Pending reboot | Whether a restart is already queued |
| `W` | Save a report file | Untick to write nothing to disk |

**Driver severity** is the part worth understanding. A missing network driver and a missing
card-reader driver are not the same emergency, so faults are graded CRITICAL, HIGH, MEDIUM, LOW.
Network is CRITICAL on its own terms: *a machine with no network driver cannot download its own
network driver*, so the report tells you to fetch it elsewhere or USB-tether a phone.

#### It checks WMI is alive before it starts

Almost every check here is a WMI query. When WMI itself is wedged, every one of them burns its full
timeout, so a run that normally takes three minutes takes twenty and produces a report whose every
hardware section says "did not answer in time".

Watching that happen is indistinguishable from the tool being broken, and it has been reported as
exactly that.

So one cheap probe runs first, with a fifteen second limit. It costs about a second on a healthy
machine, and on a sick one it turns twenty minutes of silence into a box that says WMI is not
responding, that the blank sections below are this PC and not this tool, and how to fix it. The run
carries on either way, because the checks that do not touch WMI still work and are still worth
having.

### 2. Repair and Recovery

**What it does.** A menu of 15 repairs. You choose; nothing is assumed. Anything that modifies the
machine is tagged `CHANGES`, and the menu shows a time estimate and a plain description for
whatever is highlighted.

**How it works.** It offers a restore point before any changing repair. `sfc` and `dism` run bare so
they keep their own live percentage, and because nothing can wrap them, a watchdog reads whether
their log is still being written and warns if it goes quiet. Every step is written to a repair log
as it happens, so a run that is interrupted still leaves a record.

**Defaults.** The read-only checks are on. The changing repairs are off. `SFC → DISM → SFC` is on,
with DISM skipped unless SFC finds damage, because DISM adds 10 to 40 minutes and a clean SFC
usually means there is nothing for it to do. Untick that sub-option when a machine misbehaves but
SFC insists it is fine, which is the one case a clean SFC cannot rule out.

#### Clearing temp files: there are three temp folders, not two

`%WINDIR%\Temp` and your own `%LOCALAPPDATA%\Temp` are the obvious pair. The third belongs to the
**SYSTEM account**, buried under `System32\config\systemprofile`, and every service and every
installer that has ever run as SYSTEM wrote into it. Nothing routine empties it, Disk Cleanup
included, so on a machine that has been in service for years it is frequently the largest of the
three.

And on a handed-down laptop, every account that ever signed in has a temp folder of its own. That
is where the rest of the space is.

It now clears all of it:

- Windows temp, your temp, and the SYSTEM account temp
- **Every other user profile's temp folder**
- The Windows Update download cache
- The Delivery Optimization cache, which is peer-to-peer update chunks and is routinely several GB
- Crash dumps, prefetch, and the recycle bin

Files in use are skipped rather than forced, and counted rather than hidden. Two things are
deliberately left alone and said out loud rather than silently omitted: **`C:\Temp`**, because
Windows did not create it, somebody did, and on these machines it has held the only copy of a
driver, an installer and once a set of photographs; and **`Windows.old`**, which the "old Windows
updates" repair reclaims properly through Windows' own tooling so the rollback window stays honest.

### 3. Collect-ToolLogs

Your repairs write their own log. Everything else writes somewhere on the machine you are fixing.
Finish a job and the evidence is scattered across a dozen directories on a PC you are about to hand
back.

```powershell
.\HealthReport\Collect-ToolLogs.ps1 -WhatIfOnly   # show what it would take
.\HealthReport\Collect-ToolLogs.ps1               # copy it
```

It sweeps 25 known locations across five groups:

- **Your repairs:** CBS.log, older CBS logs, dism.log, older DISM logs
- **Servicing and update:** the Windows Update client, update medic, SIH sessions, feature-update
  eligibility, SetupDiag, and Panther's `setupact`/`setuperr` for upgrades that rolled back
- **Drivers and hardware:** `setupapi.dev.log`, which is every driver install and removal in order,
  plus DDU, DriverStore Explorer, and **minidumps**, which are the difference between "it blue
  screens sometimes" and knowing which driver did it
- **Crashes:** Windows Error Reporting archives
- **Antivirus and cleanup:** Defender, Malwarebytes service logs and scan results, ADWCleaner in
  both the old and current locations, KVRT, BleachBit, BCUninstaller, OCCT, Win11Debloat

It copies into one dated folder next to the report, with an `index.md` saying what was found **and
what was not**, because absence is a finding: it usually means that tool was never run here.

It distinguishes **"nothing here"** from **"needs administrator"**. Defender's log folder, the WER
archive and parts of Panther are readable only by an administrator, and unelevated they enumerate
as empty with no error at all. Reporting that as "Defender left no log, which usually means it was
never run" is a lie in the one direction that matters, so those are listed separately under "not
readable" with the reason.

It only ever copies. Nothing is moved, nothing is deleted, and the source machine is left exactly
as it was. Files over 20 MB are skipped with the size and the reason stated.

### 4. Clear-Reports

Deletes the saved reports. Defaults to a **dry run** and prints what would go, grouped by machine.
`-Confirm` performs it; `-Keep 'MYPC'` spares one machine's records.

---

## Where reports go, and what is in them

**Both tools save next to themselves**, in the same folder as the scripts. On a USB stick that means
every machine you touch collects in one place, which is the point.

```
report-<MACHINE>-<date>_<time>.md     the health report
repairlog-<MACHINE>-<date>_<time>.txt written by the repair tool
toollogs-<MACHINE>-<date>_<time>\     collected from other tools
```

**One file per health report, in Markdown.** It opens in any editor, renders on GitHub, pastes into
a ticket, and can be handed straight to an AI to summarise. Plain text does none of that better, and
there is no HTML.

### Please read this bit

**A report contains the machine name, make, model, SERIAL NUMBER, installed software and event log
entries of the computer it ran on.** On someone else's machine, that is their data.

- Do a dozen repairs and the stick is quietly carrying a dozen hardware inventories
- Fine in your pocket; not fine if the stick is lost, lent, or imaged
- **Untick "save a report file" at the start** when you only need to look. That is what it is for
- `Clear-Reports.ps1 -Confirm` is the way to clear what has accumulated
- `.gitignore` excludes every report, which matters because a checkout of this repo **is** a working
  toolkit: you run it, it writes reports, and an unattended `git add -A` would sweep them in

**Nothing is ever transmitted.** No telemetry, no upload, no phone-home. Everything stays on the
disk it was written to.

---

## If something looks wrong

| What you see | What it is | What to do |
|---|---|---|
| Every hardware section blank, run takes forever | WMI is wedged on that PC | The tool now says so in a red box within 15 seconds. Reboot; or `net stop winmgmt` then `net start winmgmt`; or `winmgmt /salvagerepository` |
| Display frozen, nothing moving | You clicked in the window and started a text selection, which blocks all output | Press **Enter** or **Esc**. The tools disable this at startup, but if it happens on a console they could not configure, that is the fix |
| DISM parked on one percentage | Normal, for a while. It genuinely pauses while repairing files | Wait. At 10 minutes of log silence it warns; at 25 it tells you it is stuck. Then Ctrl+C, reboot, run again |
| "Repairs can half-apply" warning | A reboot is already pending | Reboot first. A pending reboot is the most common cause of DISM hanging forever |
| A `.bat` flashes and vanishes on a locked-down PC | AppLocker killed it before it could elevate | Use the Start menu shortcut, which carries the run-as-admin flag and is not evaluated by AppLocker. `Install.bat` creates one |
| Driver download fails immediately | Windows Update will not download for a standard user | Start from `Health-Report.bat`, which elevates |
| "No driver updates offered" | May be true, may be a network blip | The search retries three times. If it still says none, run the **dry run** option to prove the pipeline works |
| A check says "timed out" | That one call did not answer; everything else still ran | The report names what is missing. Usually a wedged service; a reboot clears it |
| SMART or BitLocker "needs administrator" | It was run unelevated | Use `Health-Report.bat` or the Start menu shortcut. **Do not** assume the disk is unencrypted |
| A section is missing from the report | You unticked it at the start | The report names what was left out, near the top |
| Tool diagnostics section in the report | A bug in **this tool**, not a finding about the PC | Please report it. The findings above it are unaffected |

---

## Capabilities

The tick means it has been exercised on a real machine, not merely written.

### Health report

| Section | Verified |
|---|---|
| Machine, activation, battery, storage, memory | yes |
| Drivers, with severity ranking | yes |
| Security, system state, installed software, update history | yes |
| Verdict, Markdown output, `-Unattended` | yes |
| Choose which sections to include, and whether to save | yes |
| WMI health probe before the run | yes, caught a genuinely wedged WMI |
| Elevates itself however it was started | yes |

### Repairs

| Repair | Verified |
|---|---|
| Repair system files: SFC, then DISM, then SFC | yes |
| Skip DISM unless SFC finds damage (default) | yes |
| Check the disk for errors (online, no reboot) | yes |
| Read the drive's own SMART health data | yes |
| Sweep the event log for real faults | yes |
| Reliability history | yes |
| Find devices with missing or broken drivers | yes |
| Install driver updates from Windows Update | yes, 9 drivers installed |
| Check whether this PC CAN install drivers (dry run) | yes |
| Reclaim disk space from old Windows updates | yes |
| Repair Windows Update | yes |
| Reset the network stack | yes |
| **Clear out temp files** | **yes, freed 60.61 GB on a client machine** |
| Also REPAIR what the disk check finds | partly: it ran and correctly skipped `/spotfix` on a clean disk. The repair itself has not had a damaged volume to fix |
| Test the RAM | not yet |

### Reliability

| Capability | Verified |
|---|---|
| Timeout and spinner on every slow call | yes |
| Stall watchdog on DISM and SFC | yes, caught a real one-hour DISM hang |
| Retry on transient Windows Update failures | yes |
| QuickEdit disabled so a stray click cannot freeze a run | yes |
| Tool errors recorded separately from findings about the PC | yes |
| Runs unattended with no keypress | yes |
| Per-user install, uninstall, and shortcuts that elevate | yes |

---

## Adding your own tools

The launcher is a single file, `Lazarus.hta`, and the tool list is a plain array inside it. To add
anything you already use:

**1. Put the tool in `Tools\<Name>\`.** Portable builds work best, since nothing is installed.

**2. Add one entry to the array in `Lazarus.hta`.** Copy the shape of an existing one:

```javascript
["Your Tool","Tools\\YourTool\\yourtool.exe","One line on what it is for",
 "The longer description shown when this row is highlighted. Say what it actually does and when you would reach for it.","",""],
```

| Field | What it is |
|---|---|
| 1 | Name shown in the list |
| 2 | Path from the stick root, with `\\` doubled |
| 3 | Short purpose, **44 characters max** |
| 4 | Full description, **269 characters max** |
| 5 | Tag: `AV` if antivirus will flag it, `boot` for ISOs, `temp` for one-offs, else `""` |
| 6 | Row class: `t-dang` (red) or `t-warn` (amber) for anything risky, else `""` |

**3. Optionally add a 48x48 PNG** to `Icons\` and map it in the icon list further down the same
file: `"Your Tool":"yourtool",`

**4. Check it before trusting it:**

```powershell
node Docs\validate.js .
```

That verifies every path exists, every icon resolves, and no field is over length. It also lists
tool folders present on disk but missing from the launcher, which catches the case where you copied
a tool in and forgot the entry.

---

## Ejecting safely

Use the **eject button** in the launcher. It checks nothing is still running from the stick, names
anything that is, and releases the drive.

**Then use Windows' own Safely Remove Hardware as a second check.** The launcher's eject can only see
the handles it knows to look for; an antivirus mid-scan or a file still open elsewhere can make it
report success while a write is unfinished. Two signals cost you three seconds. Losing a stick of
client reports to a half-finished write does not.

```powershell
.\Tests\Test-StickReady.ps1 -Drive D:
```

That is the fuller check before you walk away with it: volume health, every script parses, every
launcher target exists, nothing left behind, and the stick still takes a write.

---

## Checks

```powershell
.\Tests\Run-Checks.ps1                               # this checkout
.\Tests\Run-Checks.ps1 -Root D:\Tools\HealthReport   # a deployed stick
.\Tests\Test-StickReady.ps1 -Drive D:                # before unplugging
```

`Run-Checks` exits 0 or a failure count, so it can gate a commit. It verifies syntax, that every
command resolves, that no function is used before it is defined, that there are no duplicate
functions or dead variables, that no slow call was added without a progress indicator, that every
box renders as a true rectangle, that the watchdogs start and stop, that retry behaves, and that
the shared picker navigates, toggles, cancels and refuses an empty START.

It also runs each checker against `Tests/Fixtures/broken.ps1`, a deliberately wrong file, to prove
the checkers still fail when they should. That is not ceremony: the dead-variable check was silently
a no-op for a while because a hashtable key named `keys` shadowed the `.Keys` member, and it
reported a clean project having examined nothing.

---

## Design notes

Worth reading if you are modifying it. Most are scars.

**Nothing silently gives up, and nothing runs silently.** Every slow call has a visible timeout and
announces when it stalls. `Run-Checks` fails the build if a slow call is added with no spinner, no
announcement and no progress of its own.

**A switch that is accepted and does nothing is worse than one that is rejected.** `-Unattended` was
once thrown away at the elevation step, and the run then sat forever on "Press Enter to close".
`-Only`, `-Skip` and `-NoSave` were briefly inside the block that `-Unattended` skips, so
`-Unattended -Only 'E'` silently ran all eleven sections. Nothing anywhere says a dropped switch did
not work.

**No question in the middle of a run.** A prompt underneath a wall of output is indistinguishable
from a freeze. Questions come before work starts, or are queued and asked at the end. That is why
the section chooser is the first screen and not a series of prompts.

**Absence and refusal are different findings.** A folder that is empty and a folder you were not
allowed to read look identical to code and mean opposite things to a person.

**QuickEdit is disabled at startup.** One click in a Windows console starts a text selection, which
blocks every write the script makes. It looks exactly like a crash, and somebody watching a slow
repair *will* click the window.

**Log silence, not CPU, detects a hang.** DISM idles at 0% CPU while perfectly healthy, and can sit
on a percentage forever while dead. Whether its log is still being written is the only honest signal.

**DISM is what checks the component store.** SFC compares Windows against that store, so a damaged
store makes SFC report clean on a machine that plainly is not. That is why the opt-out exists rather
than the behaviour being hard-coded either way.

**Elevation belongs in the script, not only in its launcher.** A tool can be started from a `.bat`,
a shortcut, the launcher, or an already-open console, and only some of those elevate. The same is
true of console colours, which is why every script repaints on entry rather than trusting how it
was started.

**One picker, two callers.** The arrow-key chooser is fiddly code with a long history of
frame-painting bugs, so there is exactly one copy of it in `Common.ps1` and both tools call it. A
second copy would have had to re-learn every one of those bugs.

**Boxes size themselves.** Hand-counted padding drifted and left ragged edges.

---

## Licensing

The scripts, launcher and documentation here are **Apache 2.0**. See `LICENSE`. Free to use, modify
and redistribute, including commercially.

The third-party utilities the launcher lists are **not** included and are not ours to redistribute.
Each is downloaded from its own official source and remains under its own licence; see
`Docs/LICENCES.txt`. Some, such as Hiren's BootCD PE, contain Microsoft-licensed components and can
only ever be obtained from their publisher.

> **Not built yet:** an automatic `Get-Tools.ps1` to fetch each utility. Until then the third-party
> tools are a manual step. Health Report and Repair, which is the substance of this project, needs
> nothing downloaded.

---

Built by [Perpetual Technologies](https://perpetualtechnologies.co.uk). Issues and pull requests
welcome.
