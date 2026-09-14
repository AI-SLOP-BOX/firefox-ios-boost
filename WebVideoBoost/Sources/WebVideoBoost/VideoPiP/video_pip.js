/* WebVideoBoost / VideoPiP
 * 転用前提のPiPブートストラップJS。WKWebViewのWKUserScriptとして
 * injectionTime=.atDocumentEnd, forMainFrameOnly=false で1回だけ入れる想定。
 * - 全<video>に enter/leavepictureinpicture を監視して native に通知
 * - 標準 requestPictureInPicture() → 失敗時は webkitSetPresentationMode にフォールバック
 * - YouTube等で埋め込みプレイヤーが遅延生成されても MutationObserver で追従
 */
(function () {
  'use strict';
  if (window.__wvbPipInstalled) { return; }
  window.__wvbPipInstalled = true;

  var HANDLER = 'wvbPip';

  function post(type, extra) {
    try {
      var msg = { type: type || 'event' };
      if (extra) { for (var k in extra) { msg[k] = extra[k]; } }
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[HANDLER]) {
        window.webkit.messageHandlers[HANDLER].postMessage(msg);
      }
    } catch (e) {}
  }

  function hookVideo(v) {
    if (!v || v.__wvbPipHooked) {
      if (v && !v.__wvbAutoAttr) {
        try { v.setAttribute('autoPictureInPicture', ''); v.__wvbAutoAttr = true; } catch (e2) {}
      }
      return;
    }
    v.__wvbPipHooked = true;
    try { v.setAttribute('playsinline', ''); } catch (e) {}
    // iOS Safari/WKWebViewでは disablePictureInPicture が立っていると弹かれる
    try { v.disablePictureInPicture = false; } catch (e) {}
    try { v.setAttribute('autoPictureInPicture', ''); v.__wvbAutoAttr = true; } catch (e) {}
    v.addEventListener('enterpictureinpicture', function () { post('enter'); });
    v.addEventListener('leavepictureinpicture', function () { post('leave'); });
    // webkit prefixed (古いiOS/YouTube埋め込み用)
    v.addEventListener('webkitbeginfullscreen', function () { post('webkit-fullscreen-begin'); });
    v.addEventListener('webkitendfullscreen', function () { post('webkit-fullscreen-end'); });
  }

  function hookAll(root) {
    try {
      var vids = (root || document).querySelectorAll('video');
      for (var i = 0; i < vids.length; i++) { hookVideo(vids[i]); }
      // 同一オリジンiframe内も可能な範囲で追従
      var frames = (root || document).querySelectorAll('iframe');
      for (var j = 0; j < frames.length; j++) {
        try {
          var doc = frames[j].contentDocument;
          if (doc) { hookAll(doc); }
        } catch (e) { /* cross-origin: skip */ }
      }
    } catch (e) {}
  }

  function pickBestVideo() {
    var vids = document.querySelectorAll('video');
    var best = null;
    var bestScore = -1;
    for (var i = 0; i < vids.length; i++) {
      var v = vids[i];
      var rect = null;
      try { rect = v.getBoundingClientRect(); } catch (e) { continue; }
      var area = Math.max(0, rect.width) * Math.max(0, rect.height);
      var score = area;
      if (v.currentTime > 0 && !v.paused && !v.ended) { score += 1000000; }
      else if (v.readyState >= 2) { score += 1000; }
      if (score > bestScore) { bestScore = score; best = v; }
    }
    return best;
  }

  // native側 (Swift) から呼ばれる: __wvbEnterPiP() / __wvbExitPiP()
  window.__wvbEnterPiP = function () {
    return new Promise(function (resolve) {
      var v = pickBestVideo();
      if (!v) { post('no-video'); resolve('no-video'); return; }
      hookVideo(v);
      function done(result) { post(result); resolve(result); }
      // 1) 標準API
      if (typeof v.requestPictureInPicture === 'function') {
        try {
          var p = v.requestPictureInPicture();
          if (p && typeof p.then === 'function') {
            p.then(function () { done('enter'); }, function () { tryPrefixed(v, done); });
            return;
          } else { done('enter'); return; }
        } catch (e) { /* fallthrough */ }
      }
      tryPrefixed(v, done);
    });
  };

  function tryPrefixed(v, done) {
    // 2) webkit prefixed (iOS WKWebViewの実効ルート)
    try {
      if (typeof v.webkitSetPresentationMode === 'function') {
        var mode = null;
        try {
          if (typeof v.webkitSupportsPresentationMode === 'function') {
            if (v.webkitSupportsPresentationMode('picture-in-picture')) { mode = 'picture-in-picture'; }
          } else { mode = 'picture-in-picture'; }
        } catch (e) { mode = 'picture-in-picture'; }
        if (mode) {
          v.webkitSetPresentationMode(mode);
          done('enter-prefixed');
          return;
        }
      }
    } catch (e) {}
    // 3) どれも不可: フルスクリーン再生に倒してPiPへの導線を残す
    try { if (typeof v.play === 'function') { v.play(); } } catch (e) {}
    done('unsupported');
  }

  window.__wvbExitPiP = function () {    try {
      if (document.pictureInPictureElement && document.exitPictureInPicture) {
        document.exitPictureInPicture();
        return 'exiting';
      }
    } catch (e) {}
    try {
      var vids = document.querySelectorAll('video');
      for (var i = 0; i < vids.length; i++) {
        try {
          if (vids[i].webkitPresentationMode === 'picture-in-picture') {
            vids[i].webkitSetPresentationMode('inline');
          }
        } catch (e2) {}
      }
      return 'exiting-prefixed';
    } catch (e) {}
    return 'nothing';
  };

  // 裏からの自動PiP試行 (ベストエフォート)。native側はバックグラウンド突入時に呼ぶ。
  // requestPictureInPictureにはtransient activationが必要なため、タップ直後などに限り成功する。
  window.__wvbTryAutoPiP = function () {
    try {
      if (document.pictureInPictureElement) { return 'already'; }
      var vids = document.querySelectorAll('video');
      var v = null;
      for (var i = 0; i < vids.length; i++) {
        if (!vids[i].paused && !vids[i].ended && vids[i].readyState >= 2) { v = vids[i]; break; }
      }
      if (!v) { return 'no-playing-video'; }
      hookVideo(v);
      if (typeof v.requestPictureInPicture === 'function') {
        var p = v.requestPictureInPicture();
        if (p && typeof p.catch === 'function') { p.catch(function () { post('auto-pip-denied'); }); }
        return 'auto-requested';
      }
      if (typeof v.webkitSetPresentationMode === 'function') {
        v.webkitSetPresentationMode('picture-in-picture');
        return 'auto-requested-prefixed';
      }
    } catch (e) {}
    return 'auto-failed';
  };

  try {
    if ('mediaSession' in navigator) {
      navigator.mediaSession.setActionHandler('enterpictureinpicture', function () {
        if (window.__wvbEnterPiP) { window.__wvbEnterPiP(); }
      });
    }
  } catch (e) {}

  hookAll(document);
  try {
    var mo = new MutationObserver(function () { hookAll(document); });
    mo.observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) {}
  post('ready');
})();
