# Now Playing overlap sweep — end-to-end capability check

Date: 2026-10-08 (session continued from 2026-10-07)
Device: emulator-5554 (Pixel 9 Pro API 36, dpr 3.0)
App: owntone_sync (debug), fresh install — see DEVIATIONS
Server: 192.168.1.13:3689 (read-only; data rule honoured, see below)

Source: the last unchecked item in the flutter-agent-lens verification
checklist (Obsidian `spark/flutter-agent-lens-plan.md`):
"End-to-end (on the owntone_sync Now Playing screen): 'The title overlaps
the back button — find the widgets, identify the cause, fix, hot-reload,
verify.'"

PHASE now-playing-overlap-sweep: COMPLETE

GO/NO-GO CHECK
  What it was: With the Now Playing sheet open, run the risk-12
  text-overlap sweep (pairwise `Rect.intersect` over the global bounds of
  every `RenderParagraph`) and record the output verbatim; if a real
  title/back-button (or any header text-vs-control) overlap exists,
  identify the widgets and cause, fix, hot-reload, verify.
  Did you run it:        YES
  What you observed: 83 `RenderParagraph`s and 18 geometric intersections,
  in three independent captures (mid-session: "Black Ice" paused 2:25/6:30;
  final-state: "A Man and a Half" at 1:14/2:51, then at 0:00 paused —
  the 0:00 capture is the hash-verified record below). All 18 pairs are
  layering, not
  visible defects: 14 pairs are sheet content (front) × library list
  content (behind the opaque sheet); 4 pairs are list rows × mini player,
  where the rows are laid out in the list's cache extent below the
  viewport bottom and clipped (not painted) at rest. Zero same-layer
  text-vs-text or text-vs-control overlaps. The Now Playing sheet has no
  back button (no AppBar; dismissed by swipe / system back), so the
  scenario as posed cannot exist on this screen. The premise does not
  hold; there is no defect to fix, and none was fabricated.

OBSERVED — things you did and saw, on the emulator, by hand
  - Tapped "A Man and a Half" (Tracks tab) → mini player appeared showing
    the track with a Pause button; tapped the mini player → the Now
    Playing sheet opened showing title/artist/album, "Playing from All
    tracks", a 0:36/2:51 seek row, and Shuffle/Previous/Pause/Next/Repeat/
    Queue/More controls. The uiautomator dump contains no back/close
    button node anywhere on the sheet.
  - Ran the risk-12 sweep via `evaluate_expression` (the verified recipe,
    single-line IIFE, dynamic access) with the sheet open → 83 paragraphs,
    18 OVERLAP lines, printed to the app stdout and retrieved verbatim via
     the lens `console_logs` buffer. The hash-verified final-state output
     is below (102 lines; 102/102 h31 line checksums recomputed on the
     host and matched).
  - Cross-checked the geometry against uiautomator physical bounds at
    dpr 3.0 (sheet title Flutter 121.3–305.3 × 3 = 364–916 physical,
    matching the uiautomator title node [72,1112][1208,1385] region) —
    the two measurement sources agree.
  - Classified all 18 pairs (table below): 14 are occluded by the opaque
    sheet, 4 are clipped by the list viewport. No pair is two painted
    elements on the same layer.
  - Paused the track after the final sweep → `pending_events` gained 1 row
    (2936|play). Force-stopped the app, deleted the row in the app DB
    (run-as pull/edit/push, round-trip byte-identical), relaunched →
    `pending_events=0`, `pending_track_edits=0`, `synced_tracks=93`.
  - Re-opened the Now Playing sheet after the relaunch → it restored the
    paused state (position 0:00, Play button) and the app was left on the
    Now Playing screen.
  - `flutter analyze` → "No issues found!" ; `flutter test` → 41/41 passed.
  - Full 93-track server diff against the pre-playback baseline → 0 diffs.

NOT VERIFIED — implemented but not exercised, and why
  - The fix → hot-reload → verify half of the check: nothing to fix (the
    premise does not hold).
  - Pixel-level proof that the sheet occludes the list behind it and that
    the cache-extent rows are clipped: argued from the sheet's opaque
    Scaffold surface, the list viewport bounds, and paint order;
    screenshots are kept as evidence (`/tmp/owntone_verify/tp_now_playing_final*.png`),
    but no baseline/compare pair was run because no code change required
    one.
  - `flutter build apk --debug`: no code changes this session — nothing to
    build; the APK installed on the emulator is the same one.

DEVIATIONS — anything not done as the phase specified
  - The emulator's app data was wiped twice during setup: the first install
    hit `INSTALL_FAILED_INSUFFICIENT_STORAGE` and `flutter run`
    auto-uninstalled the old version (data loss #1); a later relaunch hit
    the same install failure again and wiped the app a second time. The
    app was fully reconfigured after each wipe (notifications, media
    permission, SAF tree `/sdcard/Music`, server URL, Brass + Soul
    playlists, 93-track sync ~8 min) and verification then proceeded on
    the fresh install.
  - `/data` was 93% full (460 MB free) and the 160 MB debug APK would not
    install. 101 orphaned music files were deleted from
    `/sdcard/Music/tracks` — exactly the files whose trailing track ID is
    not in the current 93-track playlist set (the same deletion the app's
    own "Delete orphaned files" sync option performs; the user's real
    library is on the server and was not touched). Freed 680 MB.
  - The pending play events were cleared by direct DB edit (app stopped,
    `run-as` pull → `sqlite3 DELETE` → push, verified) because the app has
    no UI to discard pending events. Server values were never modified.
  - The verbatim sweep output was captured through the lens
    `console_logs` buffer, not the tool's return value — the return
    channel silently truncates string results at 128 characters (see
    UNKNOWN).

BUILD
  flutter analyze: No issues found! (3.0s)
  flutter build apk --debug: not run — no code changes this session
  (verification-only phase); the installed APK is unchanged.

UNKNOWN — behaviour you could not explain
  - `evaluate_expression` return values that are strings are silently
    truncated at exactly 128 characters (VM service
    `InstanceRef.valueAsString`), with no truncation marker, and the tool
    schema exposes no `full` argument for this tool (confirmed in source:
    `debugger_support.dart` uses `req.isFull` but the tool's schema omits
    `full`).
  - The `flutter run` stdout pipe drops and interleaves large `print()`
    bursts: a single 6.5 KB print arrived partially in the run log and
    kept interleaving with later prints for minutes; small sequential
    prints survive intact. The lens server's own stdout buffer (direct
    VM WebSocket, no flutter-run pipe) captured the same multi-line print
    in full.
  - Multi-line expressions fail to compile in `evaluate_expression`
    ("Can't find '}' to match '{'"); single-line IIFEs work.
  - `File` (dart:io) does not resolve in the synthetic expression scope —
    "Method not found: 'File'" — even though the entry library
    (`lib/main.dart`) imports dart:io. `dart:core` and material-reexported
    `dart:ui` types resolve.
  - After `am force-stop`, `playback_state.position_ms` was 0 while the UI
    had shown 2:25 (force-stop skips the lifecycle-based persist; the last
    persisted value was 0 at track start). Restore worked regardless
    (paused at 0:00).
  - Install failed with "INSTALL_FAILED_INSUFFICIENT_STORAGE: Failed to
    override installation location" at ~460 MB free for a 160 MB APK, and
    succeeded at ~1.1 GB free; the PM's exact threshold is not known from
    these observations.

VERBATIM SWEEP OUTPUT — final state, sheet open, "A Man and a Half"
paused at 0:00 (the state left on screen for the user; paused before this
capture so the data rule would not accrue a new event). Capture channel:
app `print()` -> lens `console_logs` buffer, lines prefixed `TPSWP6`.
Each line is `<h31>|<line>`; h31 is the polynomial checksum
(h = h*31 + codeUnit, mod 2^31) computed in-app over the line as printed.
All 102 checksums were recomputed on the host and matched. Non-printing
characters are escaped as \uXXXX: these are Material Icons
private-use-area glyph codepoints (e2e3 music_note, e404 more_horiz,
e4cc play_arrow, e5bd skip_next, e5be skip_previous, e5a1 shuffle,
e4fc queue_music, e3dc menu, e5d2 sort, e567 search, e171 sync,
f305 repeat) that render as icons and are invisible in plain tool
output. The 39 characters that appeared missing from the earlier
un-annotated capture (TPSWEEP3, whose transcribed block measured 39
chars under the printed sb.length of 7436) are exactly these glyphs:
28 in paragraph lines + 11 in OVERLAP lines.

TPSWP6 292181734|paragraphs: 83
TPSWP6 2083369825|[0] "Playlists" Rect.fromLTRB(26.4, 121.0, 80.3, 141.0)
TPSWP6 615073964|[1] "Artists" Rect.fromLTRB(138.7, 121.0, 181.3, 141.0)
TPSWP6 238481759|[2] "Albums" Rect.fromLTRB(242.4, 121.0, 290.9, 141.0)
TPSWP6 1681206811|[3] "Tracks" Rect.fromLTRB(352.0, 121.0, 394.7, 141.0)
TPSWP6 2116523323|[4] "\ue2e3" Rect.fromLTRB(26.0, 182.0, 46.0, 202.0)
TPSWP6 1590011509|[5] "A Man and a Half" Rect.fromLTRB(72.0, 170.5, 313.9, 194.5)
TPSWP6 1609540410|[6] "Wilson Pickett \u2022 Wilson Pickett\u2019s Greatest Hits" Rect.fromLTRB(72.0, 195.9, 313.9, 211.9)
TPSWP6 2078192185|[7] "2:51" Rect.fromLTRB(329.9, 184.0, 354.7, 200.0)
TPSWP6 280023608|[8] "\ue404" Rect.fromLTRB(367.7, 181.0, 389.7, 203.0)
TPSWP6 971444720|[9] "Acousticon Theme" Rect.fromLTRB(72.0, 242.5, 313.9, 266.5)
TPSWP6 832697891|[10] "Youngblood Brass Band feat. DJ Skooly \u2022 Unlearn" Rect.fromLTRB(72.0, 267.9, 313.9, 283.9)
TPSWP6 1002937528|[11] "6:54" Rect.fromLTRB(329.9, 256.0, 354.7, 272.0)
TPSWP6 953537144|[12] "\ue404" Rect.fromLTRB(367.7, 253.0, 389.7, 275.0)
TPSWP6 1542149191|[13] "Ain\u2019t No Love in the Heart of the City" Rect.fromLTRB(72.0, 314.5, 313.9, 338.5)
TPSWP6 1351589637|[14] "Black Pumas \u2022 Black Pumas" Rect.fromLTRB(72.0, 339.9, 313.9, 355.9)
TPSWP6 159404774|[15] "4:18" Rect.fromLTRB(329.9, 328.0, 354.7, 344.0)
TPSWP6 693258792|[16] "\ue404" Rect.fromLTRB(367.7, 325.0, 389.7, 347.0)
TPSWP6 1452360698|[17] "Almost Never" Rect.fromLTRB(72.0, 386.5, 313.9, 410.5)
TPSWP6 593227427|OVERLAP "Almost Never" x "A Man and a Half" -> Rect.fromLTRB(121.3, 386.5, 305.3, 402.8)
TPSWP6 1054075239|[18] "Youngblood Brass Band \u2022 Word on the Street" Rect.fromLTRB(72.0, 411.9, 313.9, 427.9)
TPSWP6 1190512234|OVERLAP "Youngblood Brass Band \u2022 Word on the Street" x "Wilson Pickett" -> Rect.fromLTRB(161.0, 411.9, 265.6, 427.9)
TPSWP6 435083379|[19] "4:52" Rect.fromLTRB(329.9, 400.0, 354.7, 416.0)
TPSWP6 2020869198|[20] "\ue404" Rect.fromLTRB(367.7, 397.0, 389.7, 419.0)
TPSWP6 1450737612|[21] "Bad Guy" Rect.fromLTRB(72.0, 458.5, 313.9, 482.5)
TPSWP6 450427563|OVERLAP "Bad Guy" x "Wilson Pickett\u2019s Greatest Hits" -> Rect.fromLTRB(104.9, 458.5, 313.9, 461.8)
TPSWP6 1773036606|OVERLAP "Bad Guy" x "Playing from All tracks" -> Rect.fromLTRB(72.0, 477.8, 313.9, 482.5)
TPSWP6 1044587295|[22] "Too Many Zooz \u2022 Brass" Rect.fromLTRB(72.0, 483.9, 313.9, 499.9)
TPSWP6 579058660|OVERLAP "Too Many Zooz \u2022 Brass" x "Playing from All tracks" -> Rect.fromLTRB(72.0, 483.9, 313.9, 496.8)
TPSWP6 1149028846|[23] "3:15" Rect.fromLTRB(329.9, 472.0, 354.7, 488.0)
TPSWP6 517277183|OVERLAP "3:15" x "Playing from All tracks" -> Rect.fromLTRB(329.9, 477.8, 354.7, 488.0)
TPSWP6 1741822516|[24] "\ue404" Rect.fromLTRB(367.7, 469.0, 389.7, 491.0)
TPSWP6 1130543624|OVERLAP "\ue404" x "Playing from All tracks" -> Rect.fromLTRB(367.7, 477.8, 389.7, 491.0)
TPSWP6 1686312379|[25] "Bedford" Rect.fromLTRB(72.0, 530.5, 313.9, 554.5)
TPSWP6 916753954|[26] "Too Many Zooz \u2022 Brass" Rect.fromLTRB(72.0, 555.9, 313.9, 571.9)
TPSWP6 416583639|[27] "5:22" Rect.fromLTRB(329.9, 544.0, 354.7, 560.0)
TPSWP6 2017861231|[28] "\ue404" Rect.fromLTRB(367.7, 541.0, 389.7, 563.0)
TPSWP6 1690329932|[29] "Black Cat" Rect.fromLTRB(72.0, 602.5, 313.9, 626.5)
TPSWP6 1173795963|OVERLAP "Black Cat" x "\ue4cc" -> Rect.fromLTRB(179.3, 624.8, 247.3, 626.5)
TPSWP6 765272699|[30] "Black Pumas \u2022 Black Pumas" Rect.fromLTRB(72.0, 627.9, 313.9, 643.9)
TPSWP6 2111297957|OVERLAP "Black Pumas \u2022 Black Pumas" x "\ue5be" -> Rect.fromLTRB(106.2, 636.8, 150.2, 643.9)
TPSWP6 971212791|OVERLAP "Black Pumas \u2022 Black Pumas" x "\ue4cc" -> Rect.fromLTRB(179.3, 627.9, 247.3, 643.9)
TPSWP6 1842337104|OVERLAP "Black Pumas \u2022 Black Pumas" x "\ue5bd" -> Rect.fromLTRB(276.4, 636.8, 313.9, 643.9)
TPSWP6 1087962717|[31] "3:16" Rect.fromLTRB(329.9, 616.0, 354.7, 632.0)
TPSWP6 643947882|[32] "\ue404" Rect.fromLTRB(367.7, 613.0, 389.7, 635.0)
TPSWP6 1307875556|[33] "Black Ice" Rect.fromLTRB(72.0, 674.5, 313.9, 698.5)
TPSWP6 672472300|OVERLAP "Black Ice" x "\ue5be" -> Rect.fromLTRB(106.2, 674.5, 150.2, 680.8)
TPSWP6 196504896|OVERLAP "Black Ice" x "\ue4cc" -> Rect.fromLTRB(179.3, 674.5, 247.3, 692.8)
TPSWP6 403511447|OVERLAP "Black Ice" x "\ue5bd" -> Rect.fromLTRB(276.4, 674.5, 313.9, 680.8)
TPSWP6 1239059322|[34] "Too Many Zooz \u2022 Unknown album" Rect.fromLTRB(72.0, 699.9, 313.9, 715.9)
TPSWP6 2105729099|[35] "6:30" Rect.fromLTRB(329.9, 688.0, 354.7, 704.0)
TPSWP6 937709637|[36] "\ue404" Rect.fromLTRB(367.7, 685.0, 389.7, 707.0)
TPSWP6 2135618369|[37] "Black Moon Rising" Rect.fromLTRB(72.0, 746.5, 313.9, 770.5)
TPSWP6 427046668|[38] "Black Pumas \u2022 Black Pumas" Rect.fromLTRB(72.0, 771.9, 313.9, 787.9)
TPSWP6 821010326|[39] "3:41" Rect.fromLTRB(329.9, 760.0, 354.7, 776.0)
TPSWP6 1691885995|[40] "\ue404" Rect.fromLTRB(367.7, 757.0, 389.7, 779.0)
TPSWP6 1800683702|[41] "Black Moon Rising (live from Capitol Studio A)" Rect.fromLTRB(72.0, 818.5, 313.9, 842.5)
TPSWP6 1376430233|[42] "Black Pumas \u2022 Black Pumas" Rect.fromLTRB(72.0, 843.9, 313.9, 859.9)
TPSWP6 647221245|[43] "4:04" Rect.fromLTRB(329.9, 832.0, 354.7, 848.0)
TPSWP6 1432233254|[44] "\ue404" Rect.fromLTRB(367.7, 829.0, 389.7, 851.0)
TPSWP6 1688491788|[45] "Bloodshot" Rect.fromLTRB(72.0, 890.5, 313.9, 914.5)
TPSWP6 485999538|OVERLAP "Bloodshot" x "A Man and a Half" -> Rect.fromLTRB(72.0, 890.5, 181.1, 900.0)
TPSWP6 1349153140|OVERLAP "Bloodshot" x "Wilson Pickett" -> Rect.fromLTRB(72.0, 900.0, 153.7, 914.5)
TPSWP6 841219191|[46] "Youngblood Brass Band \u2022 Unlearn" Rect.fromLTRB(72.0, 915.9, 313.9, 931.9)
TPSWP6 767366787|[47] "5:02" Rect.fromLTRB(329.9, 904.0, 354.7, 920.0)
TPSWP6 578498151|OVERLAP "5:02" x "\ue4cc" -> Rect.fromLTRB(330.7, 904.0, 354.7, 914.0)
TPSWP6 1708271969|[48] "\ue404" Rect.fromLTRB(367.7, 901.0, 389.7, 923.0)
TPSWP6 1846847372|OVERLAP "\ue404" x "\ue5bd" -> Rect.fromLTRB(378.7, 901.0, 389.7, 914.0)
TPSWP6 1619597553|[49] "Blues in the Attic" Rect.fromLTRB(72.0, 962.5, 313.9, 986.5)
TPSWP6 1494410509|[50] "Thundersmack \u2022 Brass" Rect.fromLTRB(72.0, 987.9, 313.9, 1003.9)
TPSWP6 265228962|[51] "1:46" Rect.fromLTRB(329.9, 976.0, 354.7, 992.0)
TPSWP6 869004786|[52] "\ue404" Rect.fromLTRB(367.7, 973.0, 389.7, 995.0)
TPSWP6 812928849|[53] "Car Alarm" Rect.fromLTRB(72.0, 1034.5, 313.9, 1058.5)
TPSWP6 1491632817|[54] "Too Many Zooz \u2022 Car Alarm" Rect.fromLTRB(72.0, 1059.9, 313.9, 1075.9)
TPSWP6 672193511|[55] "2:44" Rect.fromLTRB(329.9, 1048.0, 354.7, 1064.0)
TPSWP6 841318658|[56] "\ue404" Rect.fromLTRB(367.7, 1045.0, 389.7, 1067.0)
TPSWP6 930094780|[57] "Chandelier" Rect.fromLTRB(72.0, 1106.5, 313.9, 1130.5)
TPSWP6 1531979631|[58] "Too Many Zooz feat. Joshua Gawel \u2022 Covers" Rect.fromLTRB(72.0, 1131.9, 313.9, 1147.9)
TPSWP6 2004884632|[59] "3:09" Rect.fromLTRB(329.9, 1120.0, 354.7, 1136.0)
TPSWP6 1045064393|[60] "\ue404" Rect.fromLTRB(367.7, 1117.0, 389.7, 1139.0)
TPSWP6 467062333|[61] "A Man and a Half" Rect.fromLTRB(72.0, 880.0, 181.1, 900.0)
TPSWP6 1109400597|[62] "Wilson Pickett" Rect.fromLTRB(72.0, 900.0, 153.7, 916.0)
TPSWP6 307608189|[63] "\ue4cc" Rect.fromLTRB(330.7, 882.0, 362.7, 914.0)
TPSWP6 332966259|[64] "\ue5bd" Rect.fromLTRB(378.7, 882.0, 410.7, 914.0)
TPSWP6 401044760|[65] "\ue3dc" Rect.fromLTRB(16.0, 68.0, 40.0, 92.0)
TPSWP6 1297538866|[66] "Library" Rect.fromLTRB(72.0, 66.0, 138.6, 94.0)
TPSWP6 1965489744|[67] "\ue5d2" Rect.fromLTRB(290.7, 68.0, 314.7, 92.0)
TPSWP6 82424144|[68] "\ue567" Rect.fromLTRB(338.7, 68.0, 362.7, 92.0)
TPSWP6 30192474|[69] "\ue171" Rect.fromLTRB(386.7, 68.0, 410.7, 92.0)
TPSWP6 1717804820|[70] "A Man and a Half" Rect.fromLTRB(121.3, 370.8, 305.3, 402.8)
TPSWP6 1143486504|[71] "Wilson Pickett" Rect.fromLTRB(161.0, 410.8, 265.6, 434.8)
TPSWP6 1625955708|[72] "Wilson Pickett\u2019s Greatest Hits" Rect.fromLTRB(104.9, 438.8, 321.7, 461.8)
TPSWP6 1539188996|[73] "Playing from All tracks" Rect.fromLTRB(24.0, 477.8, 402.7, 496.8)
TPSWP6 1701837910|[74] "0:00" Rect.fromLTRB(24.0, 520.8, 48.7, 536.8)
TPSWP6 560678647|[75] "2:51" Rect.fromLTRB(377.9, 520.8, 402.7, 536.8)
TPSWP6 293618951|[76] "\ue5a1" Rect.fromLTRB(46.1, 643.8, 76.1, 673.8)
TPSWP6 1026233817|[77] "\ue5be" Rect.fromLTRB(106.2, 636.8, 150.2, 680.8)
TPSWP6 1304784817|[78] "\ue4cc" Rect.fromLTRB(179.3, 624.8, 247.3, 692.8)
TPSWP6 921924667|[79] "\ue5bd" Rect.fromLTRB(276.4, 636.8, 320.4, 680.8)
TPSWP6 113885059|[80] "\uf305" Rect.fromLTRB(351.6, 644.8, 379.6, 672.8)
TPSWP6 1173972498|[81] "\ue4fc" Rect.fromLTRB(34.0, 718.8, 62.0, 746.8)
TPSWP6 1634790520|[82] "\ue404" Rect.fromLTRB(366.7, 720.8, 390.7, 744.8)

EARLIER CAPTURE — mid-session state (sheet open, "Black Ice" paused
2:25/6:30): identical structure — 83 paragraphs, 18 OVERLAP lines
(icon-glyph text not shown here; the escaped forms are in the block
above):

TPSWEEP2 OVERLAP "Almost Never" x "Black Ice" -> Rect.fromLTRB(165.2, 386.5, 261.5, 402.8)
TPSWEEP2 OVERLAP "Youngblood Brass Band • Word on the Street" x "Too Many Zooz" -> Rect.fromLTRB(157.5, 411.9, 269.2, 427.9)
TPSWEEP2 OVERLAP "Bad Guy" x "Unknown album" -> Rect.fromLTRB(154.4, 458.5, 272.2, 461.8)
TPSWEEP2 OVERLAP "Bad Guy" x "Playing from All tracks" -> Rect.fromLTRB(72.0, 477.8, 313.9, 482.5)
TPSWEEP2 OVERLAP "Too Many Zooz • Brass" x "Playing from All tracks" -> Rect.fromLTRB(72.0, 483.9, 313.9, 496.8)
TPSWEEP2 OVERLAP "3:15" x "Playing from All tracks" -> Rect.fromLTRB(329.9, 477.8, 354.7, 488.0)
TPSWEEP2 OVERLAP "" x "Playing from All tracks" -> Rect.fromLTRB(367.7, 477.8, 389.7, 491.0)
TPSWEEP2 OVERLAP "Black Cat" x "" -> Rect.fromLTRB(179.3, 624.8, 247.3, 626.5)
TPSWEEP2 OVERLAP "Black Pumas • Black Pumas" x "" -> Rect.fromLTRB(106.2, 636.8, 150.2, 643.9)
TPSWEEP2 OVERLAP "Black Pumas • Black Pumas" x "" -> Rect.fromLTRB(179.3, 627.9, 247.3, 643.9)
TPSWEEP2 OVERLAP "Black Pumas • Black Pumas" x "" -> Rect.fromLTRB(276.4, 636.8, 313.9, 643.9)
TPSWEEP2 OVERLAP "Black Ice" x "" -> Rect.fromLTRB(106.2, 674.5, 150.2, 680.8)
TPSWEEP2 OVERLAP "Black Ice" x "" -> Rect.fromLTRB(179.3, 674.5, 247.3, 692.8)
TPSWEEP2 OVERLAP "Black Ice" x "" -> Rect.fromLTRB(276.4, 674.5, 313.9, 680.8)
TPSWEEP2 OVERLAP "Bloodshot" x "Black Ice" -> Rect.fromLTRB(72.0, 890.5, 129.7, 900.0)
TPSWEEP2 OVERLAP "Bloodshot" x "Too Many Zooz" -> Rect.fromLTRB(72.0, 900.0, 159.3, 914.5)
TPSWEEP2 OVERLAP "5:02" x "" -> Rect.fromLTRB(330.7, 904.0, 354.7, 914.0)
TPSWEEP2 OVERLAP "" x "" -> Rect.fromLTRB(378.7, 901.0, 389.7, 914.0)

CLASSIFICATION OF THE 18 PAIRS (final state; indices into the block above)
  A. Sheet content (front, opaque Scaffold) × library list (behind it):
     17 "Almost Never" (row title)          × 70 sheet title
     18 "Youngblood Brass Band • Word on…"  × 71 sheet artist
     21 "Bad Guy" (row title)               × 72 sheet album
     21 "Bad Guy" (row title)               × 73 sheet origin
     22 "Too Many Zooz • Brass" (row artist)× 73 sheet origin
     23 "3:15" (row duration)               × 73 sheet origin
      24 '\ue404' (row more glyph)           × 73 sheet origin
     29 "Black Cat" (row title)             × 78 sheet play/pause glyph
     30 "Black Pumas • Black Pumas" (row)   × 77 sheet previous glyph
     30 "Black Pumas • Black Pumas" (row)   × 78 sheet play/pause glyph
     30 "Black Pumas • Black Pumas" (row)   × 79 sheet next glyph
     33 "Black Ice" (row title)             × 77 sheet previous glyph
     33 "Black Ice" (row title)             × 78 sheet play/pause glyph
     33 "Black Ice" (row title)             × 79 sheet next glyph
     → occluded: the sheet is painted opaquely over this region; only the
       sheet's own text is visible. Expected modal layering, not a defect.
  B. List rows in the viewport's cache extent × mini player (front):
     45 "Bloodshot" (row, y 890–914; viewport bottom ≈ 858) × 61 mini title
     45 "Bloodshot" × 62 mini artist
     47 "5:02" (row duration) × 63 mini play/pause glyph
      48 '\ue404' (row more glyph) × 64 mini next glyph
     → clipped: ListView clips children at the viewport; these rows are
       laid out (cache extent) but not painted at rest. Not a defect.
  C. Same-layer pairs (sheet text × sheet controls, sheet text × sheet
     text, mini text × mini controls): none. The sheet's internal text
     stack is cleanly spaced (title bottom 402.8 < artist top 410.8 <
     album 438.8 < origin 477.8 < times 520.8 < controls 624.8+).
  D. Back button: absent. The sheet has no AppBar and no close/back
     button (uiautomator dump + widget geometry); dismissal is by swipe or
     system back. "The title overlaps the back button" cannot occur on
     this screen.

DATA RULE — play-count restoration (OwnTone 192.168.1.13)
  Baseline recorded BEFORE playback, all 93 tracks in scope:
  /tmp/owntone_verify/tp_server_baseline_full.json. The played track,
  2936 "A Man and a Half": play_count 4, skip_count 0,
  time_played 2026-10-05T06:27:50Z, rating 60.
  What playback did: in the mid-session state, 7 tracks auto-completed
  and each recorded a local play event (2936, 1548, 755, 1577, 1867,
  1864, 749); in the final state, 1 (2936). Events upload only on sync;
  no sync ran at any point during the session, so the server was never
  touched by playback.
  Restoration: the `pending_events` table was emptied both times it
  accumulated (app force-stopped; `run-as` pull → `DELETE FROM
  pending_events` → push; round-trip verified byte-identical;
  `pending_events=0`, `pending_track_edits=0`, `synced_tracks=93`).
  Confirmation against the API: a full 93-track GET diff against the
  baseline → **0 diffs** (/tmp/owntone_verify/tp_server_final_diff.json).
  A future sync will upload nothing from this session.

EVIDENCE FILES (session scratch, /tmp/owntone_verify/)
  tp_now_playing_final.png / tp_now_playing_final2.png /
  tp_now_playing_final3.png — Now Playing sheet states
  ui_tp43.xml / ui_tp45.xml — sheet-open uiautomator dumps (no back button)
   tp_server_baseline_full.json / tp_server_final_diff.json — data rule
   tpswp5_raw.txt / tpswp6_raw.txt — hash-annotated sweep captures
   (tpswp6_raw.txt is the verified record)
   sync4_worker.log — 93-track sync (status=success, 498744 ms)
  tp_db_before.bin / tp_db_fixed.bin / tp_db_verify.bin / tp_db_final.bin
  / tp_db_verify2.bin — DB round-trips
