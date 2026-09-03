// A one-shot helper that computes the sealed byte arrays for
// [PrismSettings]. Run once during the project bootstrap:
//
//   dart run tool/prism_pack.dart
//
// It prints Dart source that can be pasted into
// `lib/prism/sealed_bytes.dart`. Never committed values change
// after that — regenerate only when a value is rotated.

// ignore_for_file: avoid_print

import 'package:lumina_fortune/prism/cloak.dart';

void _emit(String label, String plain) {
  final List<int> bytes = seal(plain);
  final StringBuffer buf = StringBuffer('const List<int> _$label = <int>[');
  for (int i = 0; i < bytes.length; i++) {
    if (i % 12 == 0) buf.write('\n  ');
    buf.write('0x${bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase()},');
    if (i % 12 != 11) buf.write(' ');
  }
  buf.write('\n];');
  print(buf.toString());

  // Round-trip check.
  final String back = unseal(bytes);
  if (back != plain) {
    print('// MISMATCH for $label: expected "$plain", got "$back"');
  } else {
    print('// OK $label');
  }
  print('');
}

void main() {
  _emit('endpoint', 'https://luminafortune.site/config.php');
  _emit('gcdBase', 'https://gcdsdk.appsflyer.com/install_data/v4.0/');
  // Populate LOCALLY before running the packer; do NOT commit
  // real values back to git — they belong only in the encoded
  // arrays inside lib/prism/sealed_bytes.dart.
  _emit('attributionKey', '');
  _emit('messagingProject', '');

  _emit('uaProduct', 'Mozilla/5.0');
  _emit('uaLinuxOpen', '(Linux; Android');
  _emit('uaBuildLabel', ' Build/');
  _emit('uaBuildClose', ')');
  _emit('uaEngineLabel', ' AppleWebKit/');
  _emit('uaEngineTail', ' (KHTML, like Gecko)');
  _emit('uaChromeLabel', ' Chrome/');
  _emit('uaMobileSafari', ' Mobile Safari/');
  _emit('chromeVersion', '149.0.7742.87');
  _emit('webkitVersion', '537.36');

  _emit('uaAppIdToken', 'appid/');
  _emit('uaAppNameToken', 'appname/');
  _emit('appNameToken', 'LuminaFortune');

  // Web-shell JS enhancers — keep short + narrow-scope. The
  // safe-area body ONLY touches the site's own CSS variables and
  // a small allow-list of decorative header classes. See
  // .cursor rules → webview_safe_area_injection.mdc.
  _emit('jsSafeArea',
      "(function(){if(window.__lfSafeAreaDone)return;window.__lfSafeAreaDone=1;var s=document.createElement('style');s.textContent=':root{--safe-area-inset-top:0px !important;--safe-area-inset-right:0px !important;--safe-area-inset-bottom:0px !important;--safe-area-inset-left:0px !important;--sat:0px !important;--sar:0px !important;--sab:0px !important;--sal:0px !important;--safe-top:0px !important;--safe-bottom:0px !important;}.gameview-mobile-header,.app-header,.js-safe-top,.header-mobile{padding-top:0 !important;margin-top:0 !important;}';document.head.appendChild(s);})();");

  _emit('jsKeyboard',
      "(function(){if(window.__lfKbGuard)return;window.__lfKbGuard=1;function field(el){return el&&(el.tagName==='INPUT'||el.tagName==='TEXTAREA'||el.isContentEditable);}function bring(){var el=document.activeElement;if(!field(el))return;var vp=window.visualViewport;if(vp){var r=el.getBoundingClientRect();var bottom=vp.offsetTop+vp.height;if(r.bottom>bottom-24||r.top<vp.offsetTop){el.scrollIntoView({behavior:'auto',block:'center'});}}else{el.scrollIntoView({behavior:'auto',block:'center'});}}document.addEventListener('focusin',function(e){if(field(e.target))setTimeout(bring,360);},true);if(window.visualViewport){var prev=window.visualViewport.height;window.visualViewport.addEventListener('resize',function(){var h=window.visualViewport.height;if(h<prev-40)setTimeout(bring,140);prev=h;});}})();");

  _emit('jsAutoplay',
      "(function(){if(window.__lfMedia)return;window.__lfMedia=1;var play=function(v){try{v.muted=true;v.playsInline=true;v.setAttribute('playsinline','');var p=v.play();if(p&&p.catch){p.catch(function(){});}}catch(_){}};var scan=function(){var vs=document.getElementsByTagName('video');for(var i=0;i<vs.length;i++){play(vs[i]);}};scan();var mo=new MutationObserver(scan);mo.observe(document.documentElement||document,{childList:true,subtree:true});})();");
}
