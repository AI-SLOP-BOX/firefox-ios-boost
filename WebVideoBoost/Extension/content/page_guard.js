/* YouTube Boost / page_guard.js (PAGE world)
 * <script>タグでページ本体に注入される。content script (isolated world) からは
 * ページのリスナーに干渉できないため、このファイルだけページ世界で動く。
 * - document.hidden / visibilityState の偽装 (YouTubeの「非表示で停止」を回避)
 * - バックグラウンド中の video.pause() を捨てる (ユーザー明示操作は通す)
 * 合図は window.postMessage({__ytbBg: true/false}, '*') で受け取る。
 */
(function () {
  'use strict';
  if (window.__ytbGuardInstalled) { return; }
  window.__ytbGuardInstalled = true;

  window.__ytbBg = false;
  window.__ytbAllowPauseOnce = false;

  try {
    Object.defineProperty(document, 'hidden', {
      get: function () { return false; }, configurable: true
    });
  } catch (e) {}
  try {
    Object.defineProperty(document, 'visibilityState', {
      get: function () { return 'visible'; }, configurable: true
    });
  } catch (e) {}

  window.addEventListener('message', function (ev) {
    var d = ev && ev.data;
    if (!d || typeof d !== 'object') { return; }
    if ('__ytbBg' in d) { window.__ytbBg = !!d.__ytbBg; }
    if (d.__ytbAllowPauseOnce) { window.__ytbAllowPauseOnce = true; }
  });

  try {
    var proto = HTMLMediaElement.prototype;
    var origPause = proto.pause;
    proto.pause = function () {
      if (window.__ytbBg && !window.__ytbAllowPauseOnce) {
        return; // バックグラウンド突入時の自動pauseを捨てる
      }
      window.__ytbAllowPauseOnce = false;
      return origPause.apply(this, arguments);
    };
  } catch (e) {}
})();
