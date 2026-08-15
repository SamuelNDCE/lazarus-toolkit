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

  Space: 23.0 GB used, 5.8 GB free (80% full) as of 2026-08-11,
  after the 7.89 GB Windows 11 ISO went back on.

================================================================
WHAT IS ON IT  -  37 tools + 9 boot ISOs
================================================================

MALWARE & FORENSICS (10)
  Autoruns           Every autostart hook, with live VirusTotal.
                     START HERE on a suspected infection.
  Process Explorer   Identify a suspicious process. VirusTotal built in.
  Process Monitor    Live file/registry/network activity.
  System Informer    Kernel-level process and handle inspection.
  ADWCleaner         Adware, PUPs, hijacked browsers. Updates on launch.
  KVRT               Kaspersky Virus Removal Tool. The ONE tool here
                     that scans a disk and removes what it finds.
                     Standalone, installs nothing, never expires.
                     Signatures are baked into the download, so
                     re-download before a job. See the licence note.
  TCPView            Every TCP/UDP connection and the process that
                     owns it. Answers "what is this phoning home to".
                     Opens a prompt with examples printed.
  Ransomware         92 free decryptors, the offline No More Ransom
  Decryptors         set plus two open-source additions. Emsisoft,
                     Avast, Bitdefender, Kaspersky. Covers STOP/Djvu,
                     Akira, Rhysida, BianLian, REvil, GandCrab,
                     DarkSide, real WannaCry (wanakiwi) and more.
                     IDENTIFY THE STRAIN FIRST. Full instructions in
                     Tools\Decryptors\README.txt

DRIVE HEALTH & RECOVERY (4)
  CrystalDiskInfo    Is this drive dying? One colour-coded verdict per
                     disk: Good, Caution or Bad, plus temperature,
                     power-on hours and reallocated sectors. Start here.
  QPhotoRec          File carving, GUI. The console build
                     photorec_win.exe sits in the same folder, as does
                     testdisk_win.exe if you ever need partition-table
                     rebuilding: the TestDisk entry was dropped from the
                     launcher on 2026-08-11 for its text-mode UI, but
                     the binary is still in Tools\TestDisk.
  Linux Reader       Reads ZFS, ext2/3/4, XFS, Btrfs, HFS+ and APFS
                     from inside Windows and copies files off them.
                     The quick route to a file on a TrueNAS pool
                     without rebooting into a live ISO. Read-only,
                     so it cannot damage the pool. Freeware from
                     DiskInternals, signed, not open source.

HARDWARE DIAGNOSTICS (4)
  OCCT               CPU, GPU, RAM and PSU stress in one tool.
  HWiNFO64           Most accurate sensor readout there is.
  CPU-Z              CPU, board, memory and SPD identification.
  GPU-Z              GPU identification, sensors, BIOS dump.

DRIVERS (3)
  Display Driver Uninstaller   Clean GPU driver removal. USE IN SAFE MODE.
  Snappy Driver Installer      Offline driver install, fetches current packs.
  DriverStore Explorer         Purge superseded driver packages. Windows
                               never deletes these and DriverStore grows
                               to many GB. Neither DDU nor Snappy does this.

NETWORK & REMOTE (5)
  WinSCP             SFTP/SCP/FTP with a dual-pane GUI.
  WindTerm           SSH, SFTP, telnet and serial in one window, with
                     tabs and split panes. Replaced PuTTY.
  Angry IP Scanner   Fast subnet sweep for live hosts. THE network
                     discovery tool here, and deliberately so: it
                     needs no driver installed on the machine you are
                     working on.
  RustDesk           Remote support. Open source, no account.
  Firefox            A clean browser that runs off the stick, keeping
                     its profile here. For when the machine's own
                     browser is hijacked or broken and you still need
                     to fetch a driver. Leaves nothing on the host.

SECURITY & CREDENTIALS (3)
  NirLauncher        398 NirSoft utilities. Password and key recovery,
                     browser forensics, network info, USB history.
                     ANTIVIRUS WILL FLAG THESE. That is expected.
                     Zip password if you re-download: nirsoft9876$
  KeePassXC          Encrypted password database for client credentials.
  Picocrypt          Encrypt a file before you carry it off site. Drag
                     in, set a password, done. Replaced VeraCrypt on
                     2026-08-11: VeraCrypt only opens TrueCrypt and
                     VeraCrypt containers, which almost never turn up
                     on a repair job, and it cost 67.8 MB against
                     Picocrypt's 2.6 MB. If you DO meet a VeraCrypt
                     volume, fetch VeraCrypt on the day.

FILES & UTILITIES (10)
  Double Commander   Dual-pane file manager. Batch rename, folder sync
                     and compare, can run elevated.
  Everything         Instant filename search across NTFS.
  WizTree 4.32       What filled the drive, in seconds. Reads the MFT.
                     TAGGED "licence": the free build is PERSONAL USE
                     ONLY. Their pricing table lists "Commercial use
                     not allowed" as a free-tier limitation and sells
                     a Supporter tier at $25-$500 by staff size. This
                     is a harder line than HWiNFO's wording. Updated
                     from 4.30 to 4.32 on 2026-08-11.
  7-Zip              Any archive. 7zr.exe alongside it is a single-file
                     extractor needing no install at all.
  Notepad++          Config and log editing.
  HxD                Hex editor. Opens PHYSICAL DRIVES AND RAM as if
                     they were files: MBR, GPT, partition tables, boot
                     sectors. That is why a hex editor is here at all.
  BCUninstaller      Uninstall ANY program, not just bloatware. Lists
                     Store apps, Steam games and orphans, removes many
                     at once, then hunts the leftover files and registry
                     keys the vendor uninstaller abandoned.
  Win11Debloat       Strip a laptop you are setting up: removes
                     preinstalled apps, disables telemetry, declutters
                     Start, Explorer and the taskbar. Numbered menu,
                     elevates itself, nothing installs. Works on
                     Windows 10 and 11. Added 2026-08-11 for a batch
                     of laptop builds. Open source, 1 MB.
  Dism++             A GUI over DISM. RestoreHealth on a corrupt
                     component store, strips superseded updates and
                     WinSxS bloat Disk Cleanup will not touch, driver
                     and boot-entry management, offline image editing.
                     MIT licensed. Needs an admin prompt.
                     CORRECTION, 2026-08-11: Dism++ is NOT "a patch
                     behind". Release tag v10.1.1002.2 ships an asset
                     named Dism++10.1.1002.1B.zip, so the 10.1.1002.1
                     binary IS the current build. Never compare a git
                     tag name to a binary version string and call the
                     difference a regression.
                     DISMTools was trialled as the replacement the same
                     day and REJECTED: not portable enough, and 123 MB
                     of .NET against Dism++'s 3.6 MB. Do not re-propose.
  BleachBit 6.0.2    Cache, temp and history cleaning. Upgraded from
                     5.0.0.2936 (2024-07-22) on 2026-08-11.
  Rufus              Write bootable USB media.

BOOT ISOs (8)  -  reboot and pick from the Ventoy menu
  Hiren's BootCD PE      Windows will not boot at all. Win11 PE, ~90 tools.
  Kaspersky Rescue       Malware that survives inside Windows. Scans with
                         Windows shut down. Updates definitions on boot.
  SystemRescue 13.02     Linux repair: ext4, XFS, btrfs, LVM, GParted,
                         ddrescue, qemu-img.
  Boot-Repair-Disk       A broken boot loader on a dual-boot machine.
                         Reinstalls GRUB, rebuilds UEFI entries, fixes a
                         Windows/Linux dual boot that stopped showing its
                         menu. One-click Recommended Repair covers most
                         cases. Build files dated 2023-12-23.
  Rescuezilla 2.6.2      Disk imaging and cloning, GUI, Clonezilla-compatible.
  MemTest86+ 8.10        RAM testing.
  TrueNAS SCALE 25.10.5  Rescue a TrueNAS box and its ZFS pools.
  Proxmox VE 9.2         Rescue a Proxmox host.


================================================================
MALWARE TRIAGE  -  READ BEFORE TRUSTING A SCAN
================================================================
  THERE IS NOW ONE SIGNATURE SCANNER: KVRT. It was added on
  2026-08-11 because everything else in this category only tells you
  what is wrong, it does not remove anything. Read its limits below
  before leaning on it.

  KVRT'S TWO CATCHES:
    1. Its signatures are baked into the .exe at download time. The
       copy on this stick ages from the day it was fetched. Before a
       real job, re-download it. It does not expire or refuse to run,
       it just quietly gets less useful.
    2. Kaspersky is a politically loaded choice. The US banned sales
       in 2024 and the UK NCSC has advised against it for government
       and critical systems since 2017. For private repair work it is
       legal and the engine is genuinely strong. If a client is
       government, defence or critical infrastructure, use Windows
       Defender and the boot-time Kaspersky Rescue Disk decision is
       yours to justify. Their licence covers home use; commercial
       use on client machines is a grey area worth reading before you
       bill for it.

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
                          you nothing. System Informer does the same
                          at kernel level if something hides.
    4. Autoruns           find persistence, check VirusTotal, remove.
                          Also where you fix hijacked .exe file
                          associations.
    5. ADWCleaner         adware and PUP sweep
    6. KVRT               full scan and removal, if you re-downloaded
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
  network first, then read Tools\Decryptors\README.txt before
  touching anything. Running the wrong decryptor can damage files.

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

  When the box will not boot at all, use its own ISO from the
  Ventoy menu (TrueNAS SCALE or Proxmox VE) rather than a generic
  live distro, so the ZFS feature flags match your pools.

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
  OCCT           Free Personal build; their site offers Purchase for more.
  Linux Reader   Freeware from DiskInternals. Free to use, but closed
                 source, and they sell a paid "VMFS Recovery" line.
  Decryptors     All free from their vendors, no licence limit. Emsisoft
                 note theirs are provided as-is with support only for
                 paying customers.

  Everything else is either open source or free for any use.

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
    Ventoy 1.1.17, RustDesk 1.4.9, Notepad++ 8.9.7, Rufus 4.15,
    KeePassXC 2.7.12, KVRT 20.0.14.0,
    Firefox 153.0.4, GSmartControl 2.0.2, System Informer
    3.2.25011.2103, VeraCrypt 1.26.29, WinSCP 6.5.6,
    GPU-Z 2.70.0, 7-Zip 26.02, CPU-Z 2.20, Angry IP Scanner 3.9.3,
    Everything 1.4.1.1032, BCUninstaller 6.2, Double Commander 1.2.8,
    Greenshot 1.3.315, DriverStore Explorer 1.0.26,
    SystemRescue 13.02, Rescuezilla 2.6.2, Proxmox VE 9.2,
    MemTest86+ 8.10, BleachBit 6.0.2
    (2026-07-05), TestDisk 7.2
    (2024-02-22), Everything 1.4.1.1032, and all six Sysinternals
    tools (Autoruns 14.3, Process Explorer 17.12, Process Monitor
    4.04, TCPView 4.19, Sigcheck 2.91).

  SYSINTERNALS IS DELIBERATELY TRIMMED, do not re-extract the full
  suite. On 2026-08-11 the folder went from 166 files / 264.6 MB to
  154 files / 91.2 MB. Removed, with reasons:
    RDCMan + RDCMan-x86   126.3 MB  RDP session manager. RustDesk and
                                    WindTerm already cover remote work.
    ZoomIt + ZoomIt64      23.2 MB  Presentation screen zoom. Not repair.
    Sysmon + Sysmon64       9.1 MB  A logging service you INSTALL, which
                                    is the opposite of a portable tool.
    ADInsight (+chm)        5.3 MB  Active Directory tracing.
    Bginfo + Bginfo64       4.7 MB  Desktop wallpaper info.
    CPUSTRES x2             4.8 MB  CPU load generator. OCCT covers this.
  Everything else in the suite is small and genuinely diagnostic, so
  it stays. Re-downloading SysinternalsSuite.zip undoes this trim.

  KNOWN OLDER, no newer release exists:
    WindTerm 2.7.0         last released 2025-03-11
    Hiren's BootCD PE 1.0.8 page dated 2024-03-06. The oldest thing
                           here, and inherent to that project's pace.
    Linux Reader 5.1       installer binary dated 2023-07-02.
    Boot-Repair-Disk       build files dated 2023-12-23. The project
                           publishes no version number, only a rolling
                           64-bit ISO.

  COULD NOT VERIFY - treat as unknown, not as current:
    HxD 2.5.0.0            mh-nexus.de publishes no machine-readable version
    TestDisk 7.2           cgsecurity.org likewise
    HWiNFO 8.51            hwinfo.com returns 403 to non-browser clients
    Kaspersky Rescue Disk  no build date published

  UNSIGNED BINARIES (normal for these projects, just so you know):
    7-Zip, HxD, Picocrypt, Angry IP Scanner,
    BCUninstaller, Double Commander, WindTerm, Dism++

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
  link. Full breakdown in Tools\Decryptors\README.txt.

  WINDOWS 11 ISO IS BACK, re-added 2026-08-11 for a batch of laptop
  builds. VERIFIED, not just downloaded:
    file        Win11_25H2_English_x64.iso, 7.89 GB
    CD001       present at 0x8001, so it is a real ISO9660 image
    label       CCCOMA_X64FRE_EN-US_DV9 (Microsoft consumer media)
    built       2026-03-08 per the volume descriptor
    contents    sources\install.wim 7.58 GB, so it is a COMPLETE
                image and not a web-installer stub
    boot        efi\boot\bootx64.efi present, so Ventoy boots it
  An exit code of 0 proves none of the above. Check them. It matters MORE for repair than for clean installs: an
  in-place repair install and DISM /RestoreHealth both need it as
  their source, so "the laptop already has Windows" is exactly the
  case that needs it, not the case that skips it. Ventoy picks it up
  from ISO\Windows\ with no further setup. Fetched with Fido, whose
  link carries a short-lived token, so download it immediately.

  HISTORICAL, kept for the reasoning: it was removed earlier the same
  day by request,
  freeing 7.89 GB. That means no DISM /RestoreHealth source and no
  in-place repair install until one is added back. Get a fresh one
  with Fido rather than a stale copy:
    Fido.ps1 -Win 11 -Rel Latest -Ed Pro -Lang English -Arch x64
  (github.com/pbatard/Fido, by the Rufus author.) Drop the ISO in
  ISO\Windows\ and Ventoy picks it up with no further setup.

  VENDOR DRIVE TOOLS (SeaTools, WD Dashboard, Samsung Magician)
  are deliberately absent. Five separate gated downloads, and
  CrystalDiskInfo already reads SMART generically. Only worth adding
  if you start doing drive firmware updates.

================================================================
KEEPING IT CURRENT
================================================================
  Sysinternals   https://download.sysinternals.com/files/SysinternalsSuite.zip
  Most others    GitHub releases or the vendor site.
  Decryptors     nomoreransom.org/en/decryption-tools.html
  ISOs           replace when you next need them, not on a schedule.

  Hit REFRESH in the launcher after changing anything. If you add a
  tool, drop a 32x32 PNG named after it into Icons\ and add a line
  to the DATA table in Lazarus.hta.

  This stick exists because the previous one (MediCat v21.12) was
  frozen at December 2021 and had rotted for 4.7 years. The whole
  point of this layout is that every piece updates independently.
