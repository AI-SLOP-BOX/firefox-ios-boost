/* WebVideoBoost / AdBlock cosmetic
 * WebKit content-blocker (block系) で取りこぼす「ページ内広告枠」を隠す。
 * uBOの cosmetic フィルタ (##.ad-banner 等) のうち、WebKitの
 * css-display-none に変換できなかった分 + 動的生成枠をMutationObserverで追う。
 * Tools/ublock_to_webkit.py が uAssets から selectors.json を吐き、
 * 本スクリプトの __WVB_COSMETIC_SELECTORS に埋め込む運用を想定。
 * デフォルトは主要な汎用セレクタのみ内包 (単体でも動作)。
 */
(function () {
  'use strict';
  if (window.__wvbCosmeticInstalled) { return; }
  window.__wvbCosmeticInstalled = true;

  var SELECTORS = (window.__WVB_COSMETIC_SELECTORS || [
    '.ad', '.ads', '.advert', '.advertisement', '.banner-ad', '.ad-banner',
    '.ad-container', '.ads-container', '.sponsored', '.sponsor',
    '[id^="div-gpt-ad"]', '[id^="google_ads"]', '[class*="google-ad"]',
    'ytd-ad-slot-renderer', 'ytd-display-ad-renderer', '.ytd-ad-slot',
    '.video-ads', '.ytp-ad-module', '.ytp-ad-overlay-container'
  ]);

  var STYLE_ID = '__wvb_cosmetic_style';
  function ensureStyle() {
    var el = document.getElementById(STYLE_ID);
    if (el) { return el; }
    el = document.createElement('style');
    el.id = STYLE_ID;
    try {
      el.textContent = SELECTORS.join(',') + '{display:none!important;}';
    } catch (e) {}
    var root = document.head || document.documentElement;
    if (root) { root.appendChild(el); }
    return el;
  }

  function sweep(root) {
    var changed = 0;
    try {
      var nodes = (root || document).querySelectorAll(SELECTORS.join(','));
      for (var i = 0; i < nodes.length; i++) {
        var n = nodes[i];
        if (n && n.style && n.style.display !== 'none') {
          n.style.setProperty('display', 'none', 'important');
          changed++;
        }
      }
    } catch (e) {}
    return changed;
  }

  ensureStyle();
  sweep(document);
  var throttle = false;
  try {
    new MutationObserver(function () {
      if (throttle) { return; }
      throttle = true;
      setTimeout(function () { throttle = false; sweep(document); }, 300);
    }).observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) {}
})();
