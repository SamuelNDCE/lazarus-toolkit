================================================================
  LAZARUS
  Portable repair, recovery and security toolkit
  Rebuilt 2026-08-11
================================================================

HOW TO OPEN IT
  Double-click  Start.bat        at the root of this drive.
  Or            Lazarus.hta      (the same thing, direct).

  It will NOT open by itself when you plug the stick in. Windows
  disabled AutoRun for USB drives in 2011 after Conficker, and it
  cannot be re-enabled reliably. That is the right behaviour for a
  security stick anyway: you would not want one that runs code the
  moment it is inserted.

  Start.bat works out its own location, so the drive letter never
  matters. It behaves the same whether the stick mounts as D:, E:
  or Z:, and so does everything the launcher runs.

THE LAUNCHER
  Search box      filters as you type. Esc clears it.
  Click a tool    shows what it is for, its size, and its path.
  Double-click    launches it immediately.
  Open folder     reveals it in Explorer.
  Refresh (top right)   re-scans the drive: re-tests every file,
                  recomputes sizes, re-reads free space. Use it
                  after DELETING a tool, to mark it missing.
                  It CANNOT show a newly added tool: the list is
                  read when the launcher loads, so after editing
                  the DATA table in Lazarus.hta you must CLOSE AND
                  REOPEN the launcher, not just hit Refresh.
  Eject (bottom right, red square)
                  names anything still running from the stick and
                  refuses until you close it, then releases the
                  drive and closes the launcher.
                  It ejects directly. It no longer opens the Windows
                  "Safely Remove Hardware" control panel: that used
                  to appear whenever the first eject attempt was
                  slow, which made a success look like a failure.
                  It now retries three times over about four seconds
                  and, only if the drive genuinely will not release,
                  says so in one message.

  Hover any small tag (VT, cli, AV, safe, boot, set, live) for what
  it means.

  TOOLS TAGGED "cli" open a command prompt that STAYS OPEN, with the
  tool on the PATH and its common commands already printed. They are
  launched through a small .bat next to the exe. Running the bare exe
  instead just prints usage and closes instantly, which looks like a
  crash. Nmap was the worked example before it was removed.

WHY THERE IS NO WIRESHARK OR NMAP  (removed 2026-08-11)
  Both need the Npcap driver INSTALLED ON THE MACHINE YOU ARE
  WORKING ON. That defeats a portable stick: you cannot capture or
  raw-scan on a client box without first installing a kernel driver
  on it.
    Wireshark  381.8 MB, and it shipped NO wpcap.dll and NO Npcap
               installer, so on a clean machine it could not capture
               at all. It was a very large pcap file viewer.
    Nmap       103.4 MB. It did at least bundle npcap-1.88.exe, but
               without that install it silently drops to connect()
               mode, where -sn, -sS and -O stop working properly.
               The symptom is a "Could not import all necessary
               Npcap functions" warning.
  Angry IP Scanner covers the realistic job, finding what is alive
  on a subnet, in 2.9 MB with no driver at all. If a job genuinely
  needs deep fingerprinting or packet capture, do it from a machine
  where Npcap is installed, or install it there deliberately.
  485 MB freed. Do not re-add either without solving the driver
  problem first.

THE INTERFACE RULE  (2026-08-11)
  Every entry must have a real interface. A NUMBERED MENU COUNTS.
  What does not count is "type the right flags or it prints usage
  and closes", which is what Sigcheck, Handle and TestDisk were.
  Win11Debloat is the worked example of the allowed case: it opens
  a menu, elevates itself, and you pick options by number.

WHY THERE ARE NO FLAGS-OR-NOTHING TOOLS LEFT  (2026-08-11)
  Every remaining entry has a real graphical interface. Sigcheck,
  TestDisk and Handle were all removed for being console-only or
  text-mode, not for being broken. Sigcheck in particular WAS
  verified working (it returns "Verified: Signed" against a known
  binary, exit 0); it was simply a pain to use.
  Where each job went:
    Sigcheck   -> Autoruns and Process Explorer already check hashes
                  against VirusTotal per-process, with a GUI.
                  sigcheck64.exe is still in Tools\Sysinternals if a
                  bulk folder sweep is ever genuinely needed.
    TestDisk   -> QPhotoRec covers recovery with a GUI.
                  testdisk_win.exe remains in the same folder.
    Handle     -> Process Explorer, Find Handle (Ctrl+F).
  If you add anything to this stick, it needs a GUI, or it does not
  go in the launcher.

WHY THERE IS NO SCREENSHOT TOOL  (Greenshot removed 2026-08-11)
  Windows has covered this natively since Win10: Win+Shift+S snips
  to the clipboard and the notification opens Snipping Tool, which
  now does arrows, boxes, highlight and redaction. Greenshot was
  3.1 MB of duplicate function with a tray process that has to be
  killed before the folder can even be deleted.

BOOTING
  Ventoy 1.1.17 (GPT, exFAT). Any .iso or .wim dropped anywhere
  under ISO\ appears in the boot menu automatically. Just copy the
  file in; there is no install step.

  Do NOT rename or reformat the VTOYEFI partition. The large data
  partition is yours to do anything with (Ventoy's own FAQ says
  so), which is why renaming it to LAZARUS was safe.

  VTOYEFI IS HIDDEN ON EVERY MACHINE  (fixed 2026-08-13)
  Windows 10 1703 and later mount every partition on a removable
  disk, so the 32 MB VTOYEFI boot partition used to show up in
  Explorer as a small extra drive on every PC this stick touched.
  Format it by accident and nothing here boots.

  Fixed on the disk, not per machine. The stick was rebuilt as GPT
  and VTOYEFI now carries GPT attributes 0xC000000000000001:
    bit 63  NoDriveLetter      Windows never assigns a letter
    bit 62  Hidden             Windows hides the volume
    bit  0  RequiredPartition  Disk Management will not delete it
  Those bits live in the GPT on the stick, so they travel with it.
  Windows reports "There is no volume associated with this
  partition" on any machine it is plugged into.

  To check, from an elevated prompt:
    diskpart
    select disk N            (whichever is the USB stick)
    select partition 2
    detail partition         expect Hidden: Yes, Required: Yes

  Get-Partition IS NO USE HERE. On removable media it leaves
  Attributes and IsHidden blank, and Set-Partition returns "Not
  Supported". Only diskpart reads the real on-disk GPT. Checking
  with the wrong tool looks identical to the bits not being set.

  DO NOT convert this stick back to MBR. On MBR the boot partition
  must carry type byte 0xEF for firmware to find it (UEFI spec 2.10
  section 5), and Windows mounts 0xEF partitions on removable disks.
  It is the same byte, so on MBR the problem has no fix. MBR would
  only be needed for a pre-UEFI machine, which is also the one thing
  GPT gives up: Ventoy rates GPT 3 stars for Legacy BIOS because the
  active flag cannot be set in the protective MBR and type 0xEE is
  refused by some old BIOS.

LAYOUT
  Start.bat / Lazarus.hta   the launcher
  Tools\                    one folder per tool
  ISO\                      bootable images, sorted by target
  Icons\                    each tool's own icon, used by the launcher
  Docs\                     this file

  Space: the launcher shows used, free and percentage along the
  bottom of its window, read live from the drive. No figure is
  written down here, because a number in a text file is out of date
  the next time anything is added.

================================================================
WHAT IS ON IT  -  31 tools + 5 boot ISOs
================================================================

  Every entry below is generated from the launcher's own table, so
  this list and what you see on screen cannot drift apart.
  Tests\Run-Checks.ps1 fails if they ever do.

MALWARE & FORENSICS (7)

  Malwarebytes                Full scan and clean, always current.
      INSTALLS Malwarebytes, it is not portable.

  Autoruns                    Find how malware survives reboots.
      Lists every autostart hook Windows has: run keys, services,
      scheduled tasks, drivers, shell extensions, codecs.

  Process Explorer            Identify a suspicious running process.
      Task Manager with a parent-child tree, loaded DLLs, open handles
      and network connections.

  Activity Log                See what has been done on a machine.
      Reads what Windows quietly keeps even when auditing was never
      on: UserAssist, which records every program a user launched and
      when, plus Prefetch and the Security log.

  Process Monitor             Work out what a program is actually doing.
      Live capture of every file, registry, network and process event.

  ADWCleaner                  Strip adware, toolbars and hijacked browsers.
      Targets PUPs, bundled junk, hijacked search providers and rogue
      extensions.

  TCPView                     See what a process is talking to.
      Live list of every TCP and UDP connection with the process that
      owns it.

DRIVE HEALTH & RECOVERY (6)

  Restore Point               Make a rollback point before you start.
      Windows 11 ships with System Protection OFF, so most machines
      have nothing to roll back to.

  Health Report and Repair    Full checkup, then fix what it found.
      Reads what Windows already knows and gives a verdict: battery
      wear, disk health, RAM, activation, Defender, firewall,
      BitLocker, BIOS age, installed programs, and every driver with
      its age.

  CrystalDiskInfo             See drive health at a glance.
      Reads SMART and gives one colour-coded verdict per drive, Good,
      Caution or Bad, with temperature, power-on hours and reallocated
      sector count.

  QPhotoRec                   Recover deleted files from a wrecked disk.
      Carves files by signature, ignoring the filesystem entirely.

  Linux Reader                Read a NAS disk from inside Windows.
      Opens ZFS, ext2/3/4, XFS, Btrfs and APFS volumes that Windows
      shows as raw unformatted space, and copies files off them.

  HxD                         Edit raw disks, RAM and boot sectors.
      Hex editor that opens physical drives and live memory as if they
      were files, which is the whole reason to carry one on a repair
      stick: MBR, GPT, partition tables and boot sectors.

HARDWARE DIAGNOSTICS (2)

  HWiNFO64                    Read every sensor accurately.
      The most complete and accurate sensor readout available: per-
      core clocks and temperatures, VRM, power draw, drive health, fan
      curves.

  GPU-Z                       Identify and verify a graphics card.
      GPU model, memory type and vendor, BIOS version, PCIe link speed
      and live sensors.

DRIVERS (3)

  Display Driver Uninstaller  Fix graphics corruption a reinstall won't.
      Completely removes GPU drivers including registry entries and
      leftover files a normal uninstall leaves behind.

  Open Drivers Folder         Every driver stored on this stick.
      Opens the Drivers folder. One folder per package, kept per
      machine. Nothing runs: driver and BIOS installers are reached
      by looking at a folder, never by one click on a menu.

  DriverStore Explorer        Purge old driver packages.
      REMOVES drivers, it does not install them.

NETWORK & REMOTE (4)

  WinSCP                      Move files to and from Linux boxes.
      Dual-pane SFTP, SCP and FTP client.

  WindTerm                    Get a shell on a server or switch.
      SSH, SFTP, telnet and serial in one window, with tabs and split
      panes.

  Angry IP Scanner            Quick sweep for live hosts.
      Fast subnet ping sweep with hostnames and open ports.

  Firefox                     Browse from a clean, separate browser.
      A hijacked or simply broken browser is normal on an infected
      machine, and you still need to fetch a driver or a tool.

FILES & UTILITIES (9)

  Double Commander            Move and compare files properly.
      Dual-pane file manager: two folders side by side, batch rename,
      folder sync and compare, built-in archive handling, and it can
      run elevated to reach paths Explorer refuses.

  Everything                  Find any file instantly by name.
      Indexes the entire MFT and returns matches as you type.

  WizTree                     Find what filled a drive, in seconds.
      Reads the NTFS Master File Table directly instead of walking
      folders, so it maps a full disk in seconds where WinDirStat
      takes many minutes.

  7-Zip                       Open literally any archive.
      Handles 7z, zip, rar, iso, wim, and extracts most installers
      directly.

  Notepad++                   Edit config and log files properly.
      Syntax highlighting, huge-file handling, regex find-and-replace
      across a folder, and correct Unix line-ending handling, which
      Notepad still mangles.

  BCUninstaller               Rip out bloatware, properly.
      Lists everything installed including Store apps, Steam games and
      orphaned entries, uninstalls many at once, then hunts the
      leftover files and registry keys the vendor's own uninstaller
      abandoned.

  Win11Debloat                Strip bloat from a laptop you are setting up.
      Removes preinstalled apps, disables telemetry and declutters
      Start, Explorer and the taskbar.

  BleachBit                   Reclaim space and clear traces.
      Clears caches, temp files, logs and browser history across many
      applications.

  Rufus                       Write a bootable USB from an ISO.
      Creates bootable installers and rescue media.

BOOT ISOs (5)  -  not launchable from here. Reboot and pick
them from the Ventoy menu.

  Hiren's BootCD PE           Windows will not boot at all.
      Bootable Windows 11 PE with about 90 free tools.

  Kaspersky Rescue            Kill malware that survives inside Windows.
      Scans with Windows shut down, so rootkits and ransomware cannot
      hide or fight back.

  SystemRescue 13.02          Repair Linux filesystems and partitions.
      Full Linux toolkit: GParted, ddrescue, LVM, ext4, XFS and btrfs
      repair, plus qemu-img for VM disk images.

  Rescuezilla 2.6.2           Image or clone a whole drive.
      Point-and-click disk imaging and cloning, Clonezilla-compatible.

  MemTest86+ 8.10             Prove whether RAM is faulty.
      Boots without an OS so it can test all memory.

================================================================
ADDING YOUR OWN TOOLS
================================================================

  ONE STEP: put the folder in Tools\ and press REFRESH.

  That is genuinely all that is required. The launcher scans Tools  on every refresh, finds any folder it has no entry for, works out
  what to run, pulls the icon out of that program's own binary, and
  lists it under "Found in the Tools folder" with a "found" pin.

  Nothing to edit. No icon to draw. No file to register.

  HOW IT PICKS WHAT TO LAUNCH
    1. A .bat or .cmd at the top of the folder wins. That is what a
       portable build ships to set its environment up before the
       program starts.
    2. Otherwise the largest .exe, searching two folders deep.
    3. Uninstallers, setups, updaters, crash reporters and similar
       helpers are skipped by name, so a program is never
       represented by the thing that runs when it breaks.

  WHY THE "found" PIN MATTERS
    It marks an entry whose category and description were GUESSED
    from a folder name rather than written by a person. A tool
    nobody has described should never look identical to one that
    has been checked, licence read and purpose written down.

  TO PROMOTE IT PROPERLY, add a line to the DATA table in
  Lazarus.hta, next to the tools already there:

    ["Your Tool","Tools\YourTool\yourtool.exe","One line on what it is for",
     "The longer description shown when the row is highlighted.","",""],

    field 1  name shown in the list
    field 2  path from the stick root, with \ doubled
    field 3  short purpose, 44 characters MAX
    field 4  full description, 269 characters MAX
    field 5  pin: "licence", "VT", "live", "safe", "boot", "set",
             "AV", "cli", or "" for none
    field 6  row colour: "t-warn" amber, "t-dang" red, "t-ok" green,
             "t-info" blue, or "" for none

  THEN CHECK IT, rather than assuming:

    node Docsalidate.js .

  That verifies every path exists, every field is within its length
  limit, every pin is defined, and lists any tool folder on disk
  that the launcher has no entry for.

  ICONS NEED NO WORK AT ALL. If you ever want to rebuild the cache
  by hand, or you have swapped a tool for a different build:

    Tools\Get-Icons.ps1            add anything missing
    Tools\Get-Icons.ps1 -Force     re-extract everything

  TO REMOVE A TOOL: delete its folder from Tools\ and delete its
  line from the DATA table. The launcher greys out anything listed
  but missing, so leaving the line behind is a visible reminder
  rather than a silent breakage.

================================================================
MALWARE TRIAGE  -  READ BEFORE TRUSTING A SCAN
================================================================
  MOST OF THIS CATEGORY ONLY TELLS YOU WHAT IS WRONG. Autoruns,
  Process Explorer, Process Monitor and TCPView find and explain.
  They remove nothing. Two things here actually remove:

    ADWCleaner    portable, free, updates itself on launch. Adware,
                  PUPs and hijacked browsers only.
    Malwarebytes  full malware scan and removal, detections always
                  current. IT INSTALLS: it is not portable, and the
                  free product is NOT licensed for business devices.
                  Read Docs\LICENCES.txt before a paid job.

  Plus Kaspersky Rescue Disk, which is a boot ISO rather than a tool
  and scans with Windows shut down.

  NEVER GOES STALE, use first:
    Autoruns and Process Explorer. Both query VirusTotal
    live, so they check current detections however old the binary
    on this stick is.

  UPDATES ITSELF ON LAUNCH (needs internet):
    ADWCleaner, Kaspersky Rescue Disk.

  ALREADY ON THE TARGET MACHINE:
    Windows Defender. It is installed and current on anything you
    will plug this into. Run a full scan from it.

  TYPICAL ORDER:
    1. Pull the network cable first, always.
    2. TCPView            what is it talking to? A process phoning
                          out to somewhere odd is the fastest tell.
    3. Process Explorer   find the process, right-click, check
                          VirusTotal, then SUSPEND it. Suspend, not
                          kill: it is reversible, so being wrong costs
                          you nothing.
    4. Autoruns           find persistence, check VirusTotal, remove.
                          Also where you fix hijacked .exe file
                          associations.
    5. ADWCleaner         adware and PUP sweep
    6. Malwarebytes       full scan and removal. It installs, so weigh
                          that and its licence first
    7. Defender           full scan on the host machine
    8. Kaspersky Rescue   boot it if anything survived

  WHY THERE IS NO rkill. It was here until 2026-08-11 and was removed
  deliberately. rkill terminates processes it believes are malicious,
  on heuristics, without asking and without a list you can review
  first. On a client machine a false positive is your problem, not
  the tool's. Suspending a named process in Process Explorer takes
  ten more seconds, is reversible, and you can see exactly what you
  touched. Nothing was lost that the remaining tools do not do
  better and more visibly.

  IF IT IS RANSOMWARE: different procedure entirely. Pull the
  network first and identify the strain before touching anything.
  Running the wrong decryptor can damage files. The offline decryptor
  set was REMOVED from this stick on 2026-08-17; fetch the right one
  on the day from nomoreransom.org/en/decryption-tools.html

================================================================
NAS AND HYPERVISOR WORK
================================================================
  The one resident tool:

    Linux Reader  Get a file off a ZFS or ext4 disk from Windows,
                  no reboot. Read-only.

  GAP, KNOW THIS BEFORE A NAS JOB: there is no bulk-transfer tool
  and no throughput tester on the stick any more. iperf3 was removed
  2026-08-11 on request, and rclone followed on the same day, also on
  request. Consequence: Linux Reader can pull individual files, but
  nothing here evacuates a whole dataset with checksums, and nothing
  here answers "is the network or the array slow".
  For a real evacuation, boot the box's own ISO from Ventoy and use
  its native tooling, or fetch rclone on the day (single 84 MB
  binary, MIT, rclone.org) rather than carrying a stale copy.

  When the box will not boot at all, use its own installer ISO
  rather than a generic live distro, so the ZFS feature flags match
  your pools. The TrueNAS and Proxmox ISOs are NOT on this stick:
  drop the one you need into ISO\ on the day and Ventoy will boot it.

================================================================
TWO THINGS THAT WILL CATCH YOU OUT
================================================================
  RAM TESTING
    Do not trust an in-Windows memory tester. The OS holds memory
    the test cannot reach, so it gives false passes. Boot
    MemTest86+ from the Ventoy menu instead.

  FILESYSTEMS
    Windows PE cannot read ZFS, ext4, XFS, btrfs or LVM. On a
    TrueNAS or Proxmox box, Hiren's shows raw unformatted-looking
    disks and nothing useful. Boot that platform's OWN ISO in
    rescue mode, or SystemRescue for plain Linux. Linux Reader
    covers the Windows-side case where the disk is attached to a
    working machine.

================================================================
LICENCES WORTH KNOWING  (fine for personal use, which is the case here)
================================================================
  HWiNFO         Their licence page: free for personal and
                 non-commercial use; a commercial environment needs
                 the paid Pro licence.
  WizTree        Free build is PERSONAL USE ONLY. Their pricing table
                 states plainly: "Commercial use not allowed". Paid
                 client work needs the Supporter tier ($25-$500 by
                 staff size). Flagged in the launcher with a "licence"
                 tag. Verified 2026-08-11.
  Linux Reader   Freeware from DiskInternals. Free to use, but closed
                 source, and they sell a paid "VMFS Recovery" line.

  Sysinternals   Autoruns, Process Explorer, Process Monitor and
                 TCPView share one licence. No commercial-use limit,
                 but you may NOT publish, lend or transfer copies,
                 and the install right covers "your devices".
  Malwarebytes   The free product is not licensed for threat removal
                 on business devices.

  Everything else is either open source or free for any use.
  Docs\LICENCES.txt has the full wording and the dates it was checked.

================================================================
VERSION STATUS  (checked 2026-08-11)
================================================================
  REMOVED 2026-08-11, deliberately, do not re-add without a reason:
    Detect It Easy   identifies packers and compilers. That is
                     reverse-engineering, not repair. You identify
                     malware by VirusTotal hash, which Autoruns and
                     Process Explorer already do. 65 MB.
    Hayabusa         Sigma rules over event logs. Real incident
                     response, genuinely good, but almost never what
                     a repair job needs. 53 MB, 5000 rule files.

  CONFIRMED CURRENT against the vendor:
    Ventoy 1.1.17, Notepad++ 8.9.7, Rufus 4.15, Firefox 153.0.4,
    WinSCP 6.5.6, GPU-Z 2.70.0, 7-Zip 26.02, Angry IP Scanner 3.9.3,
    Everything 1.4.1.1032, BCUninstaller 6.2, Double Commander 1.2.8,
    DriverStore Explorer 1.0.26, SystemRescue 13.02,
    Rescuezilla 2.6.2, MemTest86+ 8.10, BleachBit 6.0.2,
    TestDisk 7.2, and the four Sysinternals tools still carried
    (Autoruns 14.3, Process Explorer 17.12, Process Monitor 4.04,
    TCPView 4.19).

    These are VERSION numbers checked on 2026-08-11, not a claim
    about what is on the stick today. The tool list above is the
    authority for that, and it is generated rather than typed.

  SYSINTERNALS IS DELIBERATELY TRIMMED, do not re-extract the full
  suite. On 2026-08-11 the folder went from 166 files / 264.6 MB to
  154 files / 91.2 MB. Removed, with reasons:
    RDCMan + RDCMan-x86   126.3 MB  RDP session manager. WindTerm
                                    already covers remote work.
    ZoomIt + ZoomIt64      23.2 MB  Presentation screen zoom. Not repair.
    Sysmon + Sysmon64       9.1 MB  A logging service you INSTALL, which
                                    is the opposite of a portable tool.
    ADInsight (+chm)        5.3 MB  Active Directory tracing.
    Bginfo + Bginfo64       4.7 MB  Desktop wallpaper info.
    CPUSTRES x2             4.8 MB  CPU load generator. Not diagnostic.
  Everything else in the suite is small and genuinely diagnostic, so
  it stays. Re-downloading SysinternalsSuite.zip undoes this trim.

  KNOWN OLDER, no newer release exists:
    WindTerm 2.7.0         last released 2025-03-11
    Hiren's BootCD PE 1.0.8 page dated 2024-03-06. The oldest thing
                           here, and inherent to that project's pace.
    Linux Reader 5.1       installer binary dated 2023-07-02.
    Boot-Repair-Disk       no longer carried. Build files were dated
                           2023-12-23. The project
                           publishes no version number, only a rolling
                           64-bit ISO.

  COULD NOT VERIFY - treat as unknown, not as current:
    HxD 2.5.0.0            mh-nexus.de publishes no machine-readable version
    TestDisk 7.2           cgsecurity.org likewise
    HWiNFO 8.51            hwinfo.com returns 403 to non-browser clients
    Kaspersky Rescue Disk  no build date published

  UNSIGNED BINARIES (normal for these projects, just so you know):
    7-Zip, HxD, Angry IP Scanner, BCUninstaller,
    Double Commander, WindTerm

  Linux Reader is signed and the signature verifies (DiskInternals,
  Kyiv). The Windows 11 ISO carries Microsoft's own ISO9660
  structure and a 7.58 GB install.wim, both checked after download.

================================================================
KNOWN GAPS
================================================================
  SOURCEFORGE IS STILL SINKHOLED ON THIS NETWORK, and it will bite
  again. The Pi-hole allowlist covers downloads.sourceforge.net but
  NOT the apex sourceforge.net, which still resolves to 0.0.0.0
  locally while Cloudflare returns 104.18.12.149. Every SourceForge
  download link starts at the apex and redirects from there, so the
  first hop fails, in a browser as well as on the command line.

  Boot-Repair-Disk was fetched anyway on 2026-08-11 using a
  per-request DNS override, which changes nothing on the machine:
    curl --resolve sourceforge.net:443:104.18.12.149 -L -o out.iso \
      https://sourceforge.net/projects/<project>/files/<file>/download
  The real fix is to allowlist the bare domain, or the regex
  (\.|^)sourceforge\.net$ which covers the apex and every subdomain.

  TREND MICRO's Ransomware File Decryptor is DISCONTINUED, and has
  been REPLACED with open-source tools rather than chased. wanakiwi
  now covers real WannaCry and hack-petya covers the original 2016
  Petya. CERBER remains uncovered and probably always will be: the
  only free decryptor ever made handled v1 and v2 and is now a dead
  link. The decryptor set was removed from this stick on 2026-08-17.

  THERE IS NO WINDOWS 11 ISO ON THIS STICK. Checked 2026-08-17 by
  listing ISO\ : the five boot images above are all of them, and
  ISO\Windows\ holds only Hiren's BootCD PE.

  This section previously claimed the opposite. It said the ISO was
  "back, re-added 2026-08-11", listed a full verification of a 7.89 GB
  Win11_25H2_English_x64.iso, and then contradicted itself a paragraph
  later by saying it had been removed the same day. The removal is the
  part that was true. Corrected rather than deleted, because a reader
  who remembers the old text needs to know which half was wrong.

  WHAT ITS ABSENCE COSTS YOU, and what it does not:
    Provisioning a machine NOTHING. The build script runs
                         DISM /Online /Cleanup-Image /RestoreHealth
                         bare, repairing from Windows Update, and says
                         so in its own output: "no ISO needed".
    Offline repair       THIS is what you lose. With no local source
                         there is no in-place repair install, and
                         RestoreHealth cannot fall back to /Source
                         when the machine has no usable internet or a
                         broken component store. "The laptop already
                         has Windows" is exactly the case that needs
                         an ISO, not the case that skips it.

  Get a fresh one on the day rather than carrying a stale copy:
    Fido.ps1 -Win 11 -Rel Latest -Ed Pro -Lang English -Arch x64
  (github.com/pbatard/Fido, by the Rufus author.) Its link carries a
  short-lived token, so download it immediately. Drop the ISO in
  ISO\Windows\ and Ventoy picks it up with no further setup.

  VERIFY IT AFTER DOWNLOADING. An exit code of 0 proves none of this:
    CD001       present at 0x8001, so it is a real ISO9660 image
    label       CCCOMA_X64FRE_EN-US_DV9 for Microsoft consumer media
    contents    sources\install.wim near 7.5 GB, so it is a COMPLETE
                image and not a web-installer stub
    boot        efi\boot\bootx64.efi present, so Ventoy boots it

  VENDOR DRIVE TOOLS (SeaTools, WD Dashboard, Samsung Magician)
  are deliberately absent. Five separate gated downloads, and
  CrystalDiskInfo already reads SMART generically. Only worth adding
  if you start doing drive firmware updates.

================================================================
KEEPING IT CURRENT
================================================================
  Sysinternals   https://download.sysinternals.com/files/SysinternalsSuite.zip
  Most others    GitHub releases or the vendor site.
  ISOs           replace when you next need them, not on a schedule.

  Hit REFRESH in the launcher after changing anything. To ADD a tool
  rather than update one, see "ADDING YOUR OWN TOOLS" above.

  This stick exists because the previous one (MediCat v21.12) was
  frozen at December 2021 and had rotted for 4.7 years. The whole
  point of this layout is that every piece updates independently.
