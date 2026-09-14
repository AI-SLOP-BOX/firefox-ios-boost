/* WebVideoBoost / YouTube ad-skip (省メモリ版)
 * - YouTube系ドメイン以外では即return (他サイトのCPU/メモリを使わない)
 * - 旧500ms setInterval常駐を廃止: MutationObserver駆動 + 2秒フォールバック
 * - 広告なしが続けば監視を間引き・停止 (アイドル時はゼロコスト)
 */
(function () {
  'use strict';
  if (window.__wvbYtSkipInstalled) { return; }
  window.__wvbYtSkipInstalled = true;

  try {
    var host = location.hostname || '';
    if (host.indexOf('youtube.com') === -1 && host.indexOf('youtu.be') === -1 &&
        host.indexOf('youtube-nocookie.com') === -1) { return; }
  } catch (e) { return; }

  var SKIP_SELECTORS = '.ytp-skip-ad-button,.ytp-ad-skip-button,.ytp-ad-skip-button-modern,.ytp-ad-overlay-close-button';
  var FALLBACK_INTERVAL = 2000;   // 旧500ms→2000ms
  var MAX_IDLE_ROUNDS = 30;       // 約60秒広告なしでフォールバック停止
  var OBSERVE_TIMEOUT = 10 * 60 * 1000; // 10分で監視全体を停止

  var savedRate = 1;
  var savedMuted = false;
  var idleRounds = 0;
  var stopped = false;
  var observer = null;
  var timer = null;

  function clickSkip() {
    var clicked = false;
    try {
      var btns = document.querySelectorAll(SKIP_SELECTORS);
      for (var i = 0; i < btns.length; i++) {
        var b = btns[i];
        try {
          var r = b.getBoundingClientRect ? b.getBoundingClientRect() : null;
          if (r && r.width > 0 && r.height > 0) { b.click(); clicked = true; }
        } catch (e) {}
      }
    } catch (e) {}
    return clicked;
  }

  function isAdShowing() {
    try {
      if (document.querySelector('.ad-showing')) { return true; }
    } catch (e) {}
    return false;
  }

  function videos() {
    try { return document.querySelectorAll('video'); } catch (e) { return []; }
  }

  function fastForward(v) {
    try {
      if (!v.__wvbAdFF) {
        v.__wvbAdFF = true;
        savedRate = v.playbackRate || 1;
        savedMuted = v.muted;
        v.muted = true;
        try { v.playbackRate = 16; } catch (e) {}
      }
      if (isFinite(v.duration) && v.duration > 0 && isFinite(v.currentTime)) {
        var target = Math.max(0, v.duration - 0.2);
        if (target - v.currentTime > 0.5) {
          try { v.currentTime = target; } catch (e) {}
        }
      }
    } catch (e) {}
  }

  function restore(v) {
    try {
      if (v.__wvbAdFF) {
        v.__wvbAdFF = false;
        try { v.playbackRate = savedRate || 1; } catch (e) {}
        v.muted = savedMuted;
      }
    } catch (e) {}
  }

  function pass() {
    if (stopped) { return; }
    var didWork = false;
    try {
      if (clickSkip()) { didWork = true; }
      var vs = videos();
      var ad = isAdShowing();
      for (var i = 0; i < vs.length; i++) {
        if (ad) { fastForward(vs[i]); didWork = true; }
        else { restore(vs[i]); }
      }
    } catch (e) {}
    if (didWork) { idleRounds = 0; }
    else {
      idleRounds++;
      if (idleRounds >= MAX_IDLE_ROUNDS) { shutdown(); }
    }
  }

  function shutdown() {
    stopped = true;
    try { if (observer) { observer.disconnect(); } } catch (e) {}
    try { if (timer) { clearInterval(timer); } } catch (e) {}
    observer = null; timer = null;
  }

  var throttle = false;
  try {
    observer = new MutationObserver(function () {
      if (throttle || stopped) { return; }
      throttle = true;
      setTimeout(function () { throttle = false; pass(); }, 500);
    });
    observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['class'] });
  } catch (e) { observer = null; }
  timer = setInterval(pass, FALLBACK_INTERVAL);
  setTimeout(shutdown, OBSERVE_TIMEOUT);
  pass();
})();
