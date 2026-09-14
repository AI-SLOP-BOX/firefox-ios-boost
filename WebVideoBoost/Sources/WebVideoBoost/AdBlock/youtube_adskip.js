/* WebVideoBoost / YouTube ad-skip
 * YouTubeの動画内広告 (プレロール/ミッドロール) を自動スキップ/早送りする。
 * - スキップボタン出現 (.ytp-skip-ad-button, .ytp-ad-skip-button) → 自動クリック
 * - スキップ不可広告 → videoをミュート+16x倍速+末尾シークで最速消化
 * - 広告表示中は .ad-showing 検出で再生速度を上げ、終了後に復元
 * 注意: YouTubeのDOMは頻繁に変わるため、セレクタは広めに持つ。
 *       純粋なDOM操作のみで、YouTubeの利用規約・広告ポリシーとの関係は各自確認のこと。
 */
(function () {
  'use strict';
  if (window.__wvbYtSkipInstalled) { return; }
  window.__wvbYtSkipInstalled = true;

  var SKIP_SELECTORS = [
    '.ytp-skip-ad-button',
    '.ytp-ad-skip-button',
    '.ytp-ad-skip-button-modern',
    'button.ytp-ad-skip-button',
    '.ytp-ad-overlay-close-button'
  ];
  var AD_PLAYER_SELECTORS = ['.ad-showing', '.ytp-ad-player-overlay'];

  var savedRate = 1;
  var savedMuted = false;

  function clickSkip() {
    for (var i = 0; i < SKIP_SELECTORS.length; i++) {
      try {
        var btns = document.querySelectorAll(SKIP_SELECTORS[i]);
        for (var j = 0; j < btns.length; j++) {
          var b = btns[j];
          var r = b.getBoundingClientRect ? b.getBoundingClientRect() : null;
          if (r && r.width > 0 && r.height > 0) {
            try { b.click(); return true; } catch (e) {}
          }
        }
      } catch (e) {}
    }
    return false;
  }

  function isAdShowing() {
    try {
      for (var i = 0; i < AD_PLAYER_SELECTORS.length; i++) {
        if (document.querySelector(AD_PLAYER_SELECTORS[i])) { return true; }
      }
      var v = document.querySelector('video.html5-main-video');
      if (v && v.src && v.src.indexOf('googlevideo.com') === -1 && document.querySelector('.ytp-ad-module')) {
        // 保守的判定: ad moduleが可視なら広告扱い
        var m = document.querySelector('.ytp-ad-module');
        if (m && m.getBoundingClientRect && m.getBoundingClientRect().height > 0) { return true; }
      }
    } catch (e) {}
    return false;
  }

  function fastForward(video) {
    try {
      if (!video.__wvbAdFF) {
        video.__wvbAdFF = true;
        savedRate = video.playbackRate || 1;
        savedMuted = video.muted;
        video.muted = true;
        try { video.playbackRate = 16; } catch (e) {}
      }
      // 終了間際まで飛ばす (YouTubeはdurationが広告長になる)
      if (isFinite(video.duration) && video.duration > 0 && isFinite(video.currentTime)) {
        var target = Math.max(0, video.duration - 0.2);
        if (target - video.currentTime > 0.5) {
          try { video.currentTime = target; } catch (e) {}
        }
      }
    } catch (e) {}
  }

  function restore(video) {
    try {
      if (video.__wvbAdFF) {
        video.__wvbAdFF = false;
        try { video.playbackRate = savedRate || 1; } catch (e) {}
        video.muted = savedMuted;
      }
    } catch (e) {}
  }

  setInterval(function () {
    try {
      if (clickSkip()) { return; }
      var videos = document.querySelectorAll('video');
      for (var i = 0; i < videos.length; i++) {
        var v = videos[i];
        if (isAdShowing()) { fastForward(v); }
        else { restore(v); }
      }
    } catch (e) {}
  }, 500);
})();
