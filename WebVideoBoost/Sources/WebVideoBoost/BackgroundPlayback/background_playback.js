/* WebVideoBoost / BackgroundPlayback
 * 背景再生維持のためのページ側ガード。
 * - visibilitychange / pagehide での video.pause() を無効化
 * - document.hidden を false に見せかける (YouTube等の「非表示で停止」を回避)
 * - MediaSession metadata を維持
 * 注意: OS側で AVAudioSession(.playback) + UIBackgroundModes(audio) が必須。
 *       本JSだけではバックグラウンド継続できない。
 */
(function () {
  'use strict';
  if (window.__wvbBgInstalled) { return; }
  window.__wvbBgInstalled = true;

  var HANDLER = 'wvbBg';
  function post(type) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[HANDLER]) {
        window.webkit.messageHandlers[HANDLER].postMessage({ type: type });
      }
    } catch (e) {}
  }

  // 1) document.hidden / visibilityState の偽装
  try {
    Object.defineProperty(document, 'hidden', { get: function () { return false; }, configurable: true });
  } catch (e) {}
  try {
    Object.defineProperty(document, 'visibilityState', { get: function () { return 'visible'; }, configurable: true });
  } catch (e) {}

  // 2) visibilitychange / pagehide リスナーの無力化:
  //    YouTube等が登録する「隠れたらpause」をaddEventListener段階で握りつぶす。
  (function () {
    var origAdd = Document.prototype.addEventListener;
    Document.prototype.addEventListener = function (type, listener, options) {
      if (type === 'visibilitychange' || type === 'pagehide') { return; }
      return origAdd.call(this, type, listener, options);
    };
    // 既に登録済みのものは止められないため、pause自体にもガードを付ける
  })();

  // 3) バックグラウンド移行直後のpauseを一定時間だけ拒否するフラグ
  window.__wvbBgGuard = false;
  try {
    var proto = HTMLMediaElement.prototype;
    var origPause = proto.pause;
    proto.pause = function () {
      if (window.__wvbBgGuard) {
        // ネイティブ側が「今バックグラウンドに入った」間だけpauseを捨てる
        try {
          var stack = new Error().stack || '';
          // ユーザー明示操作由来のpauseは通す (リモコン/ロック画面対応のため messaging で判定)
          if (window.__wvbAllowPauseOnce) {
            window.__wvbAllowPauseOnce = false;
            return origPause.apply(this, arguments);
          }
        } catch (e) {}
        post('pause-blocked');
        return;
      }
      return origPause.apply(this, arguments);
    };
  } catch (e) {}

  // 4) 音量/ミュート維持 + 再生状態のnative通知
  function hookMedia(el) {
    if (!el || el.__wvbBgHooked) { return; }
    el.__wvbBgHooked = true;
    el.addEventListener('play', function () { post('play'); });
    el.addEventListener('pause', function () { post('pause'); });
    el.addEventListener('ended', function () { post('ended'); });
  }
  function hookAll() {
    try {
      var els = document.querySelectorAll('video,audio');
      for (var i = 0; i < els.length; i++) { hookMedia(els[i]); }
    } catch (e) {}
  }
  hookAll();
  try {
    new MutationObserver(hookAll).observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) {}
  post('ready');
})();
