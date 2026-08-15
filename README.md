# Lazarus Toolkit

A USB repair stick for secondhand and ex-corporate Windows machines. It surveys a PC using
data Windows already has, tells you plainly what is wrong with it, and then repairs the
things it found, using Windows' own tools rather than installing anything.

Built for a real job: getting donated ex-corporate laptops fit to hand to a child at a
coding club, and repairing client machines. Everything in it exists because something went
wrong on an actual machine.

## What you get

**Health and Handover Report** (read-only, safe on any machine)

Battery wear, SMART data, disk health, Windows activation, BitLocker status, security
software, driver problems ranked by severity, stale and generic drivers, event log faults,
reliability history, and whether a laptop is actually fit to give to a child.

It writes three files next to itself:

| File | For |
|---|---|
| `report-<PC>-<date>.txt` | The full record of the run, including timings |
| `report-<PC>-<date>.md` | The readable copy. Paste into a ticket, or hand to an AI |
| *(nothing else)* | It never phones home and never uploads |

**Repair and Recovery** (changes the machine, and says so)

A menu of 15 repairs you pick from, each with a plain description, a time estimate, and a
`CHANGES` tag if it modifies anything. Offers a restore point first.

SFC and DISM system file repair, driver updates from Windows Update, disk checking, RAM
testing, Windows Update repair, network stack reset, component store cleanup, and a driver
installer dry run that proves a machine *can* install drivers without installing any.

## Capabilities

Everything below is built and running. The tick means it has been exercised on a real machine,
not merely written.

### Health and Handover Report (read-only, safe on any machine)

| Section | What it establishes | Verified |
|---|---|---|
| Machine | Make, model, serial, BIOS version and age, CPU, GPU, motherboard | yes |
| Windows activation | Licensed or not, and by which channel | yes |
| Battery | Design vs full-charge capacity, wear percentage, cycle count | yes |
| Storage | SMART data, power-on hours, reallocated sectors, SSD write life, free space | yes |
| Memory | Installed sticks, speed, slots used | yes |
| Drivers | Missing or broken devices **ranked by severity**, generic-vs-vendor drivers, driver ages | yes |
| Security | Defender state, firewall profiles, BitLocker, registered antivirus, Absolute/Computrace | yes |
| System state | Restore points, pending reboots, uptime | yes |
| Installed software | Full program list, cross-checked against the registry | yes |
| Windows Update history | Recent installs and failures | yes |
| Verdict | Ready to hand over / usable with notes / not ready | yes |

Outputs a `.txt` record and a `.md` copy for pasting into a ticket or handing to an AI.
`-Unattended` surveys a machine and exits with no keypress.

### Repair and Recovery (a menu; anything that changes the machine says so)

| Repair | Verified |
|---|---|
| Repair system files: SFC, then DISM, then SFC | yes |
| Skip DISM unless SFC finds damage (default, saves 10 to 40 min) | yes |
| Check the disk for errors (online, no reboot) | yes |
| Read the drive's own SMART health data | yes |
| Sweep the event log for real faults | yes |
| Reliability history: what has been failing, and when | yes |
| Find devices with missing or broken drivers | yes |
| Install driver updates from Windows Update | yes, 9 drivers installed |
| Check whether this PC CAN install drivers (a dry run) | yes |
| Also REPAIR what the disk check finds | not yet |
| Clear out temp files | not yet |
| Reclaim disk space from old Windows updates | yes |
| Repair Windows Update | yes |
| Reset the network stack | yes |
| Test the RAM | not yet |

Offers a restore point before anything that changes the machine. Driver installs delete their
downloaded packages afterwards and leave the DriverStore intact, so a bad driver can still be
rolled back.

### Reliability

| Capability | Verified |
|---|---|
| Timeout and spinner on every slow call | yes |
| Stall watchdog on DISM and SFC (warns at 10 min, escalates at 25) | yes, caught a real 1-hour DISM hang |
| Retry on transient Windows Update failures | yes |
| QuickEdit disabled so a stray click cannot freeze the run | yes |
| Internal tool errors recorded separately from findings about the PC | yes |
| Runs unattended with no keypress | yes |

### Launcher

An HTA menu over roughly 40 third-party utilities (malware, disk, hardware, network, boot
media). The utilities are **not** included here; see Licensing.

## Getting started

```powershell
git clone https://github.com/perpetual-technologies/lazarus-toolkit.git
cd lazarus-toolkit
.\HealthReport\Health-Report.bat
```

The health report and repair tools work on their own with no setup. They use only what
Windows already provides, so there is nothing to download for those.

The **full launcher** (`Lazarus.hta`) additionally lists around 40 third-party utilities.
Those are not included here and are not ours to redistribute (see Licensing), so a fresh
clone shows them as missing until you put them in `Tools\<Name>\`. `Docs/validate.js`
reports which paths the launcher expects:

```powershell
node Docs\validate.js .
```

> **Not built yet:** an automatic `Get-Tools.ps1` that fetches each utility from its own
> official source. Until that exists, the third-party tools are a manual step. The health
> report and repair scripts, which are the substance of this project, do not need it.

Unattended, for surveying a machine with no keypresses:

```powershell
.\HealthReport\Health-Report.ps1 -Unattended
```

Read-only checks only. Nothing that changes a machine ever runs without somebody saying yes.

## Requirements

Windows 10 or 11, Windows PowerShell 5.1 (built in, no install). Administrator for the
checks that need it: SMART, BitLocker, battery capacity, and any repair.

## Checks

```powershell
.\Tests\Run-Checks.ps1                          # this checkout
.\Tests\Run-Checks.ps1 -Root D:\Tools\HealthReport   # a deployed stick
```

Exits 0 or a failure count, so it can gate a commit. It verifies syntax, that every command
resolves, that no function is used before it is defined, that there are no duplicate
functions or dead variables, and the project-specific rules (unique menu keys, the QuickEdit
guard present, the DISM watchdog wired to both DISM calls).

It also runs each checker against `Tests/Fixtures/broken.ps1`, a deliberately wrong file, to
prove the checkers themselves still fail when they should. That is not ceremony: the
dead-variable check was silently a no-op for a while, because a hashtable key named `keys`
shadowed the `.Keys` member, and it reported a clean project having examined nothing.

## Design notes

These are worth reading if you are modifying it, because most are scars.

**Nothing silently gives up, and nothing runs silently.** Every slow call has a visible
timeout and announces when it stalls. A check that quietly returns nothing is worse than one
that fails loudly, because you then act on a report with a hole in it. `Tests/Run-Checks.ps1`
enforces this: it fails the build if a slow call is added with no spinner, no announcement,
and no progress of its own.

**Anything that can wedge is watched.** `sfc` and `dism` must run bare to keep their own live
percentage, so nothing can wrap them. A stall watch reads whether their log is still being
written and warns at 10 minutes, escalating at 25 to "almost certainly stuck, Ctrl+C and
reboot". Log silence is the signal, not CPU: DISM idles at 0% CPU while perfectly healthy.

**Transient failures retry.** A Windows Update search that fails because WiFi blinked reads
as "no drivers offered" on a machine with nine waiting. It retries three times, announcing
each attempt, and gives up loudly. It never retries an empty result, because "nothing found"
is a legitimate answer.

**No question in the middle of a run.** A prompt underneath a wall of output is
indistinguishable from a freeze. Questions are asked before work starts, or queued and
asked at the end.

**QuickEdit is disabled at startup.** A single click in a Windows console starts a text
selection, which blocks every write the script makes. It looks exactly like a crash, and
somebody watching a slow repair will click the window.

**Log silence, not CPU, detects a hang.** DISM can sit at 0% CPU while healthy, and can
wedge forever while showing a percentage. The watchdog checks whether `dism.log` is still
being written and warns at 10 minutes, escalating at 25.

**DISM runs even when SFC is clean.** SFC compares Windows against the component store, so
a damaged store makes SFC report clean wrongly. A clean SFC is when DISM is most worth
running. There is an opt-out for when you want the quick version.

## Licensing

The scripts, launcher and documentation here are Apache 2.0. See `LICENSE`.

The third-party utilities are **not** included and are not ours to redistribute. Each is
downloaded from its own official source by `Get-Tools.ps1` and remains under its own
licence. See `Docs/LICENCES.txt`. Some, such as Hiren's BootCD PE, contain Microsoft
licensed components and can only ever be fetched from their publisher.

## A warning about reports

The reports contain the machine name, make, model, **serial number**, installed software
and event log entries for whatever computer they were run on. On other people's machines
that is their data. `.gitignore` excludes them, but check before you commit or share.

---

Built by [Perpetual Technologies](https://perpetualtechnologies.co.uk). Free to use, and
pull requests welcome.
