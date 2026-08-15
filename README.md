# Lazarus Toolkit

A USB repair stick for secondhand and ex-corporate Windows machines. It surveys a PC using
data Windows already has, tells you plainly what is wrong with it, and then repairs what it
found using Windows' own tools. Nothing is installed on the machine being fixed.

Built for a real job: getting donated ex-corporate laptops fit to hand to a child at a coding
club, and repairing client machines. Every guard in it exists because something went wrong on
an actual computer.

---

## Quick start

**Double-click `Start.bat`.** That opens the launcher, which is the menu everything is run
from. It is the only thing you need to remember.

```powershell
git clone https://github.com/perpetual-technologies/lazarus-toolkit.git
cd lazarus-toolkit
.\Start.bat
```

`Start.bat` opens `Lazarus.hta`, the graphical launcher. From there you pick a tool and it
runs. The launcher also lists around 40 third-party utilities, which are not bundled here (see
Licensing), so a fresh clone shows those as missing until you add them; the health report and
repair tools work immediately with nothing downloaded.

Prefer to skip the launcher and go straight to the main tool:

```powershell
.\HealthReport\Health-Report.bat
```

That elevates itself, runs the read-only survey, then offers the repair menu. Nothing that
changes a machine happens without you saying yes.

| I want to | Run |
|---|---|
| **Open the launcher (start here)** | **`Start.bat`** |
| Survey a machine, change nothing | `Health-Report.bat` and answer **n** at the end |
| Survey it with no keypresses at all | `Health-Report.ps1 -Unattended` |
| Go straight to repairs | `Repair-Health.ps1` |
| Delete the saved reports | `Clear-Reports.ps1 -Confirm` |
| Check the toolkit itself is sound | `Tests\Run-Checks.ps1` |
| Check a USB stick before unplugging | `Tests\Test-StickReady.ps1 -Drive D:` |

**Requirements:** Windows 10 or 11, Windows PowerShell 5.1 (built in). Administrator for SMART
data, BitLocker, battery capacity, driver installs, and any repair.

---

## The tools

### 1. Health and Handover Report

**What it does.** Reads everything Windows already knows about the machine and turns it into a
verdict: *ready to hand over*, *usable with notes*, or *not ready*.

**How it works.** Every check runs on a background thread with its own timeout and a live
spinner, so a slow call shows a climbing counter rather than a frozen screen. If a check does
not answer in time it says so and the run continues, and the report says which answer is
missing. It never writes to the machine and never sends anything anywhere.

**What it checks.**

| Section | What you learn |
|---|---|
| Machine | Make, model, serial, BIOS version and age, CPU, GPU, motherboard |
| Windows activation | Licensed or not, and by which channel |
| Battery | Design vs full-charge capacity, wear percentage, cycle count |
| Storage | SMART data, power-on hours, reallocated sectors, SSD write life, free space |
| Memory | Sticks installed, speed, slots used |
| Drivers | Broken devices **ranked by severity**, generic-vs-vendor drivers, driver ages |
| Security | Defender, firewall, BitLocker, registered antivirus, Absolute/Computrace |
| System state | Restore points, pending reboots, uptime |
| Installed software | Full program list, cross-checked against the registry |
| Windows Update | Recent installs and failures |

**Driver severity** is the part worth understanding. A missing network driver and a missing
card-reader driver are not the same emergency, so faults are graded CRITICAL, HIGH, MEDIUM,
LOW. Network is CRITICAL on its own terms: *a machine with no network driver cannot download
its own network driver*, so the report tells you to fetch it elsewhere or USB-tether a phone.

### 2. Repair and Recovery

**What it does.** A menu of 15 repairs. You choose; nothing is assumed. Anything that modifies
the machine is tagged `CHANGES`, and the menu shows a time estimate and a plain description
for whatever is highlighted.

**How it works.** It offers a restore point before any changing repair. `sfc` and `dism` run
bare so they keep their own live percentage, and because nothing can wrap them, a watchdog
reads whether their log is still being written and warns if it goes quiet. Every step is
written to a repair log as it happens, so a run that is interrupted still leaves a record.

**Defaults.** The read-only checks are on. The changing repairs are off. `SFC → DISM → SFC`
is on, with DISM skipped unless SFC finds damage, because DISM adds 10 to 40 minutes and a
clean SFC usually means there is nothing for it to do. Untick that sub-option when a machine
misbehaves but SFC insists it is fine, which is the one case a clean SFC cannot rule out.

### 3. Clear-Reports

Deletes the saved reports. Defaults to a **dry run** and prints what would go, grouped by
machine. `-Confirm` performs it; `-Keep 'MYPC'` spares one machine's records.

---

## Where reports go, and what is in them

**Both tools save next to themselves**, in the same folder as the scripts. On a USB stick that
means every machine you touch collects in one place, which is the point.

```
report-<MACHINE>-<date>_<time>.txt    the full record, including timings
report-<MACHINE>-<date>_<time>.md     the readable copy
repairlog-<MACHINE>-<date>_<time>.txt written by the repair tool
```

There is no HTML. The `.txt` is the complete record and is what the tools read back; the `.md`
is the one to paste into a ticket, email to an owner, or hand to an AI to summarise.

### Please read this bit

**A report contains the machine name, make, model, SERIAL NUMBER, installed software and event
log entries of the computer it ran on.** On someone else's machine, that is their data.

- Do a dozen repairs and the stick is quietly carrying a dozen hardware inventories
- Fine in your pocket; not fine if the stick is lost, lent, or imaged
- `Clear-Reports.ps1 -Confirm` is the way to clear them
- `.gitignore` excludes every report, which matters because a checkout of this repo **is** a
  working toolkit: you run it, it writes reports, and an unattended `git add -A` would sweep
  them in

**Nothing is ever transmitted.** No telemetry, no upload, no phone-home. Everything stays on
the disk it was written to.

---

## If something looks wrong

| What you see | What it is | What to do |
|---|---|---|
| Display frozen, nothing moving | You clicked in the window and started a text selection, which blocks all output | Press **Enter** or **Esc**. The tools disable this at startup, but if it happens on a console they could not configure, that is the fix |
| DISM parked on one percentage | Normal, for a while. It genuinely pauses while repairing files | Wait. At 10 minutes of log silence it warns; at 25 it tells you it is stuck. Then Ctrl+C, reboot, run again |
| "Repairs can half-apply" warning | A reboot is already pending | Reboot first. A pending reboot is the most common cause of DISM hanging forever |
| Driver download fails immediately | Windows Update will not download for a standard user | Start from `Health-Report.bat`, which elevates |
| "No driver updates offered" | May be true, may be a network blip | The search retries three times. If it still says none, run the **dry run** option to prove the pipeline works |
| A check says "timed out" | That one call did not answer; everything else still ran | The report names what is missing. Usually a wedged service; a reboot clears it |
| SMART or BitLocker "needs administrator" | It was run unelevated | Use `Health-Report.bat`. **Do not** assume the disk is unencrypted |
| Menu looks stacked or ragged | An older build | Update. The menu paints in a single write now |
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
| Verdict, `.txt` + `.md` output, `-Unattended` | yes |

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
| Clear out temp files | yes, freed 1.68 GB on a client machine |
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

---

## Checks

```powershell
.\Tests\Run-Checks.ps1                               # this checkout
.\Tests\Run-Checks.ps1 -Root D:\Tools\HealthReport   # a deployed stick
.\Tests\Test-StickReady.ps1 -Drive D:                # before unplugging
```

`Run-Checks` exits 0 or a failure count, so it can gate a commit. It verifies syntax, that
every command resolves, that no function is used before it is defined, that there are no
duplicate functions or dead variables, that no slow call was added without a progress
indicator, that every box renders as a true rectangle, that the watchdogs start and stop, and
that retry behaves.

It also runs each checker against `Tests/Fixtures/broken.ps1`, a deliberately wrong file, to
prove the checkers still fail when they should. That is not ceremony: the dead-variable check
was silently a no-op for a while because a hashtable key named `keys` shadowed the `.Keys`
member, and it reported a clean project having examined nothing.

---

## Design notes

Worth reading if you are modifying it. Most are scars.

**Nothing silently gives up, and nothing runs silently.** Every slow call has a visible timeout
and announces when it stalls. `Run-Checks` fails the build if a slow call is added with no
spinner, no announcement and no progress of its own.

**No question in the middle of a run.** A prompt underneath a wall of output is
indistinguishable from a freeze. Questions come before work starts, or are queued and asked at
the end.

**QuickEdit is disabled at startup.** One click in a Windows console starts a text selection,
which blocks every write the script makes. It looks exactly like a crash, and somebody watching
a slow repair *will* click the window.

**Log silence, not CPU, detects a hang.** DISM idles at 0% CPU while perfectly healthy, and can
sit on a percentage forever while dead. Whether its log is still being written is the only
honest signal.

**DISM is what checks the component store.** SFC compares Windows against that store, so a
damaged store makes SFC report clean on a machine that plainly is not. That is why the opt-out
exists rather than the behaviour being hard-coded either way.

**Boxes size themselves.** Hand-counted padding drifted and left ragged edges.

---

## Licensing

The scripts, launcher and documentation here are **Apache 2.0**. See `LICENSE`. Free to use,
modify and redistribute, including commercially.

The third-party utilities the launcher lists are **not** included and are not ours to
redistribute. Each is downloaded from its own official source and remains under its own
licence; see `Docs/LICENCES.txt`. Some, such as Hiren's BootCD PE, contain Microsoft-licensed
components and can only ever be obtained from their publisher.

> **Not built yet:** an automatic `Get-Tools.ps1` to fetch each utility. Until then the
> third-party tools are a manual step. The health report and repair scripts, which are the
> substance of this project, need nothing downloaded.

---

Built by [Perpetual Technologies](https://perpetualtechnologies.co.uk). Issues and pull
requests welcome.
