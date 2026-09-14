/* YouTube Boost / popup */
(function () {
  'use strict';
  var defaults = { pipButton: true, bgGuard: true, autoPip: true };
  var pipEl = document.getElementById('pip');
  var bgEl = document.getElementById('bg');
  var autoEl = document.getElementById('auto');
  var msgEl = document.getElementById('msg');

  function say(t) { msgEl.textContent = t; }

  try {
    chrome.storage.sync.get(defaults, function (items) {
      pipEl.checked = !!items.pipButton;
      bgEl.checked = !!items.bgGuard;
      autoEl.checked = !!items.autoPip;
    });
  } catch (e) { say('設定の読み込みに失敗'); }

  function save() {
    try {
      chrome.storage.sync.set({ pipButton: pipEl.checked, bgGuard: bgEl.checked, autoPip: autoEl.checked });
    } catch (e) { say('設定の保存に失敗'); }
  }
  pipEl.addEventListener('change', save);
  bgEl.addEventListener('change', save);
  autoEl.addEventListener('change', save);

  document.getElementById('go').addEventListener('click', function () {
    try {
      chrome.tabs.query({ active: true, currentWindow: true }, function (tabs) {
        if (!tabs || !tabs[0]) { say('タブが見つかりません'); return; }
        chrome.tabs.sendMessage(tabs[0].id, { cmd: 'enter-pip' }, function (res) {
          if (chrome.runtime.lastError) { say('YouTubeのタブで押してください'); return; }
          say(res && res.result === 'no-video' ? '動画が見つかりません' : 'PiP要求を送信しました');
        });
      });
    } catch (e) { say('送信に失敗しました'); }
  });
})();
