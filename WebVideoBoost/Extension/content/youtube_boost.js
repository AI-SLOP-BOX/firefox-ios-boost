/* YouTube Boost / youtube_boost.js (ISOLATED world, document_start)
 * - page_guard.js をページ世界に注入
 * - 全videoにPiPフローティングボタンを付ける
 * - 非表示化をpage世界に通知 (バックグラウンド再生維持)
 * - popupからの {cmd:'enter-pip' / 'toggle-bg'} を受ける
 * 設定は chrome.storage.sync: {pipButton: true, bgGuard: true}
 */
(function () {
  'use strict';
  if (window.__ytbBoostInstalled) { return; }
  window.__ytbBoostInstalled = true;

  var settings = { pipEnabled: true, pipButton: true, bgGuard: true, autoPip: true };
  try {
    if (chrome && chrome.storage && chrome.storage.sync) {
      chrome.storage.sync.get(settings, function (items) {
        if (items) { settings = items; applySettings(); }
      });
      chrome.storage.onChanged.addListener(function (changes, area) {
        if (area !== 'sync') { return; }
        Object.keys(changes).forEach(function (k) { settings[k] = changes[k].newValue; });
        applySettings();
      });
    }
  } catch (e) {}

  // --- page世界ガードの注入 ---
  function injectGuard() {
    try {
      if (document.documentElement && !document.getElementById('__ytb_guard_tag')) {
        var s = document.createElement('script');
        s.id = '__ytb_guard_tag';
        s.src = chrome.runtime.getURL('content/page_guard.js');
        s.onload = function () { try { this.remove(); } catch (e2) {} };
        document.documentElement.appendChild(s);
      }
    } catch (e) {}
  }
  injectGuard();

  function notifyBg(hidden) {
    try {
      window.postMessage({ __ytbBg: settings.bgGuard && hidden }, '*');
    } catch (e) {}
  }
  try {
    document.addEventListener('visibilitychange', function () {
      notifyBg(document.hidden);
      if (document.hidden) { tryAutoPip(); }
    });
  } catch (e) {}

  // --- 裏からの自動PiP試行 (ベストエフォート) ---
  // 仕様上 requestPictureInPicture にはtransient activation (タップ等の余韻・数秒) が必要で、
  // 裏からの無条件自動突入は不可。ただし「再生ボタンを押してすぐ裏に回した」等の場合は
  // activationが生きていて成功するので、黙って1回だけ試す。失敗は無視。
  // Chromium系では video.autoPictureInPicture 属性も付与 (タブ切替で自動PiP対応ブラウザ用)。
  // iOSの「設定 > 一般 > ピクチャインピクチャ > 自動で開始」ONだと、OS側の自動PiPも効く。
  var autoTriedForHide = false;
  function tryAutoPip() {
    if (!settings.pipEnabled || !settings.autoPip || autoTriedForHide) { return; }
    autoTriedForHide = true;
    setTimeout(function () { autoTriedForHide = false; }, 5000);
    var v = pickBestVideo();
    if (!v || v.paused || v.ended) { return; }
    if (document.pictureInPictureElement) { return; }
    hookVideo(v);
    try {
      if (typeof v.requestPictureInPicture === 'function') {
        var p = v.requestPictureInPicture();
        if (p && typeof p.catch === 'function') { p.catch(function () {}); }
      } else if (typeof v.webkitSetPresentationMode === 'function') {
        v.webkitSetPresentationMode('picture-in-picture');
      }
    } catch (e) {}
  }

  try {
    if ('mediaSession' in navigator) {
      navigator.mediaSession.setActionHandler('enterpictureinpicture', function () {
        if (settings.pipEnabled) { enterPiP(); }
      });
    }
  } catch (e) {}

  // --- PiP ---
  function hookVideo(v) {
    if (!v || v.__ytbHooked) {
      if (v && !v.__ytbAutoAttr) {
        try { v.setAttribute('autoPictureInPicture', ''); v.__ytbAutoAttr = true; } catch (e2) {}
      }
      return;
    }
    v.__ytbHooked = true;
    try { v.setAttribute('playsinline', ''); } catch (e) {}
    try { v.disablePictureInPicture = false; } catch (e) {}
    try { v.setAttribute('autoPictureInPicture', ''); v.__ytbAutoAttr = true; } catch (e) {}
  }

  function pickBestVideo() {
    var vids = document.querySelectorAll('video');
    var best = null, bestScore = -1;
    for (var i = 0; i < vids.length; i++) {
      var v = vids[i], rect = null;
      try { rect = v.getBoundingClientRect(); } catch (e) { continue; }
      var score = Math.max(0, rect.width) * Math.max(0, rect.height);
      if (v.currentTime > 0 && !v.paused && !v.ended) { score += 1000000; }
      else if (v.readyState >= 2) { score += 1000; }
      if (score > bestScore) { bestScore = score; best = v; }
    }
    return best;
  }

  function enterPiP() {
    if (!settings.pipEnabled) { return 'disabled'; }
    var v = pickBestVideo();
    if (!v) { return 'no-video'; }
    hookVideo(v);
    if (typeof v.requestPictureInPicture === 'function') {
      try {
        var p = v.requestPictureInPicture();
        if (p && typeof p.then === 'function') {
          p.then(function () {}, function () { prefixed(v); });
          return 'requested';
        }
        return 'requested';
      } catch (e) { /* fallthrough */ }
    }
    return prefixed(v);
  }

  function prefixed(v) {
    try {
      if (typeof v.webkitSetPresentationMode === 'function') {
        v.webkitSetPresentationMode('picture-in-picture');
        return 'requested-prefixed';
      }
    } catch (e) {}
    try { v.play(); } catch (e2) {}
    return 'unsupported';
  }

  // --- フローティングPiPボタン ---
  var BTN_ID = '__ytb_pip_btn';
  function ensureButton() {
    if (!settings.pipEnabled || !settings.pipButton) { removeButton(); return; }
    if (document.getElementById(BTN_ID)) { return; }
    var host = document.querySelector('#movie_player, #player, ytd-watch-flexy, body');
    if (!host && !document.body) { return; }
    var btn = document.createElement('button');
    btn.id = BTN_ID;
    btn.type = 'button';
    btn.title = 'Picture in Picture';
    btn.textContent = 'PiP';
    btn.addEventListener('click', function (ev) {
      try { ev.stopPropagation(); } catch (e) {}
      enterPiP();
    });
    (document.body || host).appendChild(btn);
  }
  function removeButton() {
    try {
      var b = document.getElementById(BTN_ID);
      if (b) { b.remove(); }
    } catch (e) {}
  }
  function applySettings() {
    ensureButton();
    try { notifyBg(document.hidden); } catch (e) {}
  }

  // --- 監視 ---
  function sweep() {
    try {
      var vids = document.querySelectorAll('video');
      for (var i = 0; i < vids.length; i++) { hookVideo(vids[i]); }
    } catch (e) {}
    ensureButton();
  }
  sweep();
  var throttle = false;
  try {
    new MutationObserver(function () {
      if (throttle) { return; }
      throttle = true;
      setTimeout(function () { throttle = false; sweep(); }, 1000);
    }).observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) {}

  // --- popupからの指示 ---
  try {
    if (chrome && chrome.runtime && chrome.runtime.onMessage) {
      chrome.runtime.onMessage.addListener(function (msg, sender, sendResponse) {
        if (!msg || typeof msg.cmd !== 'string') { return; }
        if (msg.cmd === 'enter-pip') { sendResponse({ result: enterPiP() }); }
        else if (msg.cmd === 'allow-pause-once') {
          try { window.postMessage({ __ytbAllowPauseOnce: true }, '*'); } catch (e) {}
          sendResponse({ result: 'ok' });
        }
      });
    }
  } catch (e) {}
})();
