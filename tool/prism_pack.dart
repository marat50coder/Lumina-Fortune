// ─────────────────────────────────────────────────────────────
// prism_pack — regenerate the sealed byte arrays for prism_core.
// ─────────────────────────────────────────────────────────────
// Run during bootstrap or whenever a credential is rotated:
//
//   dart run tool/prism_pack.dart
//
// It reads the real secret values from `tool/prism.secret.json`
// (gitignored — copy `tool/prism.secret.example.json` and fill
// it in locally) and prints the `Idx::… => obfbytes!(&[…])` match
// arms to paste into `rust/prism_core/src/sealed.rs`.
//
// The committed repo therefore carries NO plaintext endpoint,
// secret, AppsFlyer key or Firebase project — only the sealed
// byte arrays inside the compiled `.so`. The non-secret UA / JS
// scaffolding fragments live in this file because they are not
// credentials (they are visible on the wire anyway).
//
// Rule: never commit `tool/prism.secret.json`, and never leave a
// credential empty here — an empty value silently disables the
// gate (`PrismSettings.gateReady`).

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:lumina_fortune/prism/cloak.dart';

/// Secret values (endpoint / relay secret / attribution key /
/// firebase project / gcd base) — loaded from the untracked file.
const String _secretFile = 'tool/prism.secret.json';

/// Non-secret scaffolding — safe to live in source.
const Map<String, String> _public = <String, String>{
  'UaProduct': 'Mozilla/5.0',
  'UaLinuxOpen': '(Linux; Android',
  'UaBuildLabel': ' Build/',
  'UaBuildClose': ')',
  'UaEngineLabel': ' AppleWebKit/',
  'UaEngineTail': ' (KHTML, like Gecko)',
  'UaChromeLabel': ' Chrome/',
  'UaMobileSafari': ' Mobile Safari/',
  'ChromeVersion': '149.0.7742.87',
  'WebkitVersion': '537.36',
  'UaAppIdToken': 'appid/',
  'UaAppNameToken': 'appname/',
  'AppNameToken': 'LuminaFortune',
};

const Map<String, String> _js = <String, String>{
  'JsSafeArea':
      "(function(){if(window.__lfSafeAreaDone)return;window.__lfSafeAreaDone=1;var s=document.createElement('style');s.textContent=':root{--safe-area-inset-top:0px !important;--safe-area-inset-right:0px !important;--safe-area-inset-bottom:0px !important;--safe-area-inset-left:0px !important;--sat:0px !important;--sar:0px !important;--sab:0px !important;--sal:0px !important;--safe-top:0px !important;--safe-bottom:0px !important;}.gameview-mobile-header,.app-header,.js-safe-top,.header-mobile{padding-top:0 !important;margin-top:0 !important;}';document.head.appendChild(s);})();",
  'JsKeyboard':
      "(function(){if(window.__lfKbGuard)return;window.__lfKbGuard=1;function field(el){return el&&(el.tagName==='INPUT'||el.tagName==='TEXTAREA'||el.isContentEditable);}function bring(){var el=document.activeElement;if(!field(el))return;var vp=window.visualViewport;if(vp){var r=el.getBoundingClientRect();var bottom=vp.offsetTop+vp.height;if(r.bottom>bottom-24||r.top<vp.offsetTop){el.scrollIntoView({behavior:'auto',block:'center'});}}else{el.scrollIntoView({behavior:'auto',block:'center'});}}document.addEventListener('focusin',function(e){if(field(e.target))setTimeout(bring,360);},true);if(window.visualViewport){var prev=window.visualViewport.height;window.visualViewport.addEventListener('resize',function(){var h=window.visualViewport.height;if(h<prev-40)setTimeout(bring,140);prev=h;});}})();",
  'JsAutoplay':
      "(function(){if(window.__lfMedia)return;window.__lfMedia=1;var play=function(v){try{v.muted=true;v.playsInline=true;v.setAttribute('playsinline','');var p=v.play();if(p&&p.catch){p.catch(function(){});}}catch(_){}};var scan=function(){var vs=document.getElementsByTagName('video');for(var i=0;i<vs.length;i++){play(vs[i]);}};scan();var mo=new MutationObserver(scan);mo.observe(document.documentElement||document,{childList:true,subtree:true});})();",
  'JsHop':
      "(function(){if(window.__lfHop)return;window.__lfHop=1;function go(u){if(!u)return;try{window.location.assign(u);}catch(e){try{window.location.href=u;}catch(e2){}}}window.open=function(u){if(u)go(u);return window;};function bind(){if(!document.addEventListener)return;document.addEventListener('click',function(e){var n=e.target;while(n&&n.tagName!=='A')n=n.parentElement;if(!n)return;var t=(n.getAttribute('target')||'').toLowerCase();var h=n.href||'';if(!h||h==='#'||h.indexOf('javascript:')===0)return;if(t==='_blank'||t==='_new'){e.preventDefault();e.stopPropagation();go(h);}},true);}if(document.documentElement)bind();else document.addEventListener('DOMContentLoaded',bind);})();",
};

void _emitRust(String idx, String plain) {
  final List<int> bytes = seal(plain);
  final StringBuffer buf = StringBuffer('        Idx::$idx => obfbytes!(&[');
  for (int i = 0; i < bytes.length; i++) {
    if (i % 12 == 0) buf.write('\n            ');
    buf.write('0x${bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase()},');
    if (i % 12 != 11) buf.write(' ');
  }
  buf.write('\n        ]).to_vec(),');
  print(buf.toString());

  final String back = unseal(bytes);
  if (back != plain) {
    stderr.writeln('// MISMATCH for $idx');
    exitCode = 1;
  }
  print('');
}

void main() {
  final File f = File(_secretFile);
  if (!f.existsSync()) {
    stderr.writeln(
      'Missing $_secretFile — copy tool/prism.secret.example.json and fill '
      'in the real values first.',
    );
    exitCode = 2;
    return;
  }
  final Map<String, dynamic> secret =
      jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;

  const List<String> required = <String>[
    'endpoint',
    'relaySecret',
    'attributionKey',
    'messagingProject',
    'gcdBase',
  ];
  for (final String key in required) {
    final Object? v = secret[key];
    if (v is! String || v.isEmpty) {
      stderr.writeln('$_secretFile: "$key" is missing or empty — the gate '
          'will not arm until every credential is set.');
      exitCode = 2;
      return;
    }
  }

  print('// ==== paste into rust/prism_core/src/sealed.rs ====\n');
  // Secret arms — index names must match sealed.rs::Idx.
  _emitRust('Endpoint', secret['endpoint'] as String);
  _emitRust('RelaySecret', secret['relaySecret'] as String);
  _emitRust('GcdBase', secret['gcdBase'] as String);
  _emitRust('AttributionKey', secret['attributionKey'] as String);
  _emitRust('MessagingProject', secret['messagingProject'] as String);

  // Non-secret scaffolding.
  _public.forEach(_emitRust);
  _js.forEach(_emitRust);
}
