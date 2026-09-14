/* YouTube Boost / popup */
(function () {
  'use strict';
  var defaults = { pipEnabled: true, pipButton: true, bgGuard: true, autoPip: true };
  var pipOnEl = document.getElementById('pipOn');
  var pipEl = document.getElementById('pip');
  var bgEl = document.getElementById('bg');
  var autoEl = document.getElementById('auto');
  var msgEl = document.getElementById('msg');

  function say(t) { msgEl.textContent = t; }

  try {
    chrome.storage.sync.get(defaults, function (items) {
      pipOnEl.checked = !!items.pipEnabled;
      pipEl.checked = !!items.pipButton;
      bgEl.checked = !!items.bgGuard;
      autoEl.checked = !!items.autoPip;
    });
  } catch (e) { say('設定の読み込みに失敗'); }

  function save() {
    try {
      chrome.storage.sync.set({
        pipEnabled: pipOnEl.checked,
        pipButton: pipEl.checked,
        bgGuard: bgEl.checked,
        autoPip: autoEl.checked
      });
    } catch (e) { say('設定の保存に失敗'); }
  }
  pipOnEl.addEventListener('change', save);
  pipEl.addEventListener('change', save);
  bgEl.addEventListener('change', save);
  autoEl.addEventListener('change', save);

  document.getElementById('go').addEventListener('click', function () {
    try {
      chrome.tabs.query({ active: true, currentWindow: true }, function (tabs) {
        if (!tabs || !tabs[0]) { say('タブが見つかりません'); return; }
        chrome.tabs.sendMessage(tabs[0].id, { cmd: 'enter-pip' }, function (res) {
          if (chrome.runtime.lastError) { say('YouTubeのタブで押してください'); return; }
          var r = res && res.result;
          say(r === 'no-video' ? '動画が見つかりません' :
              r === 'disabled' ? 'PiP機能がOFFです' : 'PiP要求を送信しました');
        });
      });
    } catch (e) { say('送信に失敗しました'); }
  });
})();
