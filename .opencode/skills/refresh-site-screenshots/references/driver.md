# Driver tooling — verified against this repo (profile build, Oct 2026)

`package:flutter_driver`'s client hangs (`waitUntilNoTransientCallbacks`); the
MCP dart flutter_driver tool misreports the extension. Raw JSON-RPC to the VM
service calling `ext.flutter.driver` answers instantly. Keep these files in a
scratch dir **outside** the repo (e.g. `/tmp/drvpkg`) so `flutter run`'s
native-assets lock never blocks `dart run`.

## drv.dart — one-shot driver RPC (exit 0 = success)

```dart
import 'dart:convert';
import 'dart:io';
Future<void> main(List<String> args) async {
  final ws = await WebSocket.connect(
      Platform.environment['VM_URI']!.replaceFirst('http', 'ws'));
  final b = ws.asBroadcastStream();
  var id = 0;
  Future<Map<String, dynamic>> rpc(String m, [Map<String, dynamic>? p]) async {
    final n = ++id;
    ws.add(jsonEncode({'jsonrpc': '2.0', 'id': n, 'method': m, 'params': p ?? {}}));
    final ev = await b.firstWhere((e) => jsonDecode(e as String)['id'] == n);
    return jsonDecode(ev as String) as Map<String, dynamic>;
  }
  final vm = await rpc('getVM');
  final isolateId = (vm['result']['isolates'] as List).first['id'] as String;
  final msg = await rpc('ext.flutter.driver',
      {'isolateId': isolateId, ...jsonDecode(args[0])});
  await ws.close();
  if (msg['error'] != null) { stderr.writeln(msg['error']); exit(1); }
  final r = msg['result'] as Map<String, dynamic>;
  if (r['isError'] == true) { stderr.writeln(r['response']); exit(1); }
  exit(0);
}
```

Use `VM_URI` from the `flutter run` log (`available at: http://…/`). Run:
`VM_URI=... dart drv.dart '{"command":"get_health"}'`.

For commands that return data (`get_text`, `waitFor` diagnostics), print
`msg['result']['response']` instead of exit code.

## Verified command forms

| Need | Command JSON |
|---|---|
| Enable semantics (once per session; re-run after back navigations if uiautomator goes blind) | `{"command":"set_semantics","enabled":true}` |
| Wait/gate | `{"command":"waitFor","finderType":"ByText","text":"…","timeout":"10000"}` |
| Tap text | `{"command":"tap","finderType":"ByText","text":"…"}` |
| Tap icon/button by tooltip | `{"command":"tap","finderType":"ByTooltipMessage","text":"Search"}` (`Open navigation menu`, `Pause`, `Queue`, `Clear queue`, `Back`) |
| Tap field to focus | `{"command":"tap","finderType":"ByType","type":"EditableText"}` — key is **`type`**, not `text` |
| Type text | focus first, then `{"command":"enter_text","text":"…"}` — enters into the focused field; `adb input text` does NOT reach it |
| Ambiguous duplicate text | Descendant finder; **nested finders are JSON-encoded strings**: `{"command":"tap","finderType":"Descendant","of":"{\"finderType\":\"ByType\",\"type\":\"ElevatedButton\"}","matching":"{\"finderType\":\"ByText\",\"text\":\"Sync\"}","matchRoot":false,"firstMatchOnly":true}` |
| Open now-playing sheet | `{"command":"tap","finderType":"ByType","type":"MiniPlayer"}` |

**Not available / broken:** `scrollUntilVisible` → `Unsupported command kind`.
`get_text` with `ByType Text` hangs. No hot restart / `ext.flutter.inspector`
in profile builds — relaunch `flutter run` to reset app state (prefs/DB
persist; app returns to Library).

## Scroll-aware find (lazy ListViews build only visible rows)

```bash
find_scroll() { # <text> [max]
  local t="$1" max="${2:-12}"
  for _ in $(seq 1 "$max"); do
    dart drv.dart "{\"command\":\"waitFor\",\"finderType\":\"ByText\",\"text\":\"$t\",\"timeout\":\"2000\"}" >/dev/null 2>&1 && return 0
    adb -s "$SERIAL" shell input swipe 640 1800 640 900 250 >/dev/null
  done; return 1; }
```
Swipe back down (`640 900 → 640 1800`) before capturing so the shot starts at
the top.

## uiautomator helper (native dialogs + Flutter content-desc)

Dump to `/sdcard` and `cat` it — `exec-out uiautomator dump /dev/stdout`
truncates. Retry the dump 3–5 times when empty (animations). Flutter exposes
**content-desc** (row summaries like `Good People\nThundersmack • Brass\nRated
5.0 of 5\n2:58`, tabs as `Albums\nTab 3 of 4`), usually no `text` — decode
`&#10;` entities (`html.unescape`) before matching. Native dialogs
(`com.google.android.permissioncontroller`, `com.google.android.documentsui`)
expose real `text` and are tapped by center of `bounds`.

Gate every capture with driver `waitFor`s (authoritative); use the dump as a
second check.
