import Foundation

enum RuntimeNavigationBridge {
  static let currentSessionIDScript = """
    (() => {
      const projection = globalThis.__DSH_NATIVE_CONVERSATION_PROJECTION__;
      if (!projection || typeof projection.currentSessionID !== 'function') return null;
      return projection.currentSessionID();
    })()
    """

  private static let deepSeekOnlySettingsPolicy = """
    (dialog => {
      const clean = value => (value || '').replace(/\\s+/g, ' ').trim();
      const hide = element => {
        element.hidden = true;
        element.style.setProperty('display', 'none', 'important');
        element.setAttribute('aria-hidden', 'true');
        element.setAttribute('data-rabbisir-deepseek-only', 'hidden');
      };
      const apply = () => {
        const addProviderLabels = new Set([
          '添加提供方',
          '添加自定义提供方',
          'Add provider',
          'Add a custom provider'
        ]);
        for (const button of dialog.querySelectorAll('button')) {
          if (addProviderLabels.has(clean(button.textContent))) hide(button);
        }
        for (const actions of dialog.querySelectorAll('[class*="addActions"]')) {
          hide(actions);
        }
        for (const button of dialog.querySelectorAll('button[aria-label]')) {
          const label = clean(button.getAttribute('aria-label'));
          if (!/^(编辑|删除|Edit|Delete) /i.test(label)) continue;
          const row = button.closest('li');
          if (row && !/DeepSeek/i.test(clean(row.textContent))) hide(row);
        }
        dialog.setAttribute('data-rabbisir-model-policy', 'deepseek-only');
      };
      apply();
      window.__rabbisirSettingsPolicyObserver?.disconnect();
      const observer = new MutationObserver(apply);
      observer.observe(dialog, { childList: true, subtree: true });
      window.__rabbisirSettingsPolicyObserver = observer;
      return true;
    })
    """

  static let settingsPolicyInstallationScript = """
    (() => {
      const clean = value => (value || '').replace(/\\s+/g, ' ').trim();
      const applyRabbisirPolicy = \(deepSeekOnlySettingsPolicy);
      const scan = () => {
        for (const dialog of document.querySelectorAll('[role="dialog"][aria-modal="true"]')) {
          const hasSettingsNavigation = [...dialog.querySelectorAll('button')].some(button =>
            /^(模型|Models)$/i.test(clean(button.textContent))
          );
          if (hasSettingsNavigation) applyRabbisirPolicy(dialog);
        }
      };
      scan();
      window.__rabbisirSettingsSurfaceObserver?.disconnect();
      const observer = new MutationObserver(scan);
      observer.observe(document.documentElement, { childList: true, subtree: true });
      window.__rabbisirSettingsSurfaceObserver = observer;
      return true;
    })()
    """

  static let nativeMenuOwnershipInstallationScript = """
    (() => {
      const clean = value => (value || '').replace(/\\s+/g, ' ').trim();
      const hide = element => {
        element.hidden = true;
        element.style.setProperty('display', 'none', 'important');
        element.setAttribute('aria-hidden', 'true');
        element.setAttribute('data-rabbisir-native-menu-owned', 'true');
      };
      const apply = () => {
        for (const button of document.querySelectorAll('button')) {
          const text = clean(button.textContent);
          const label = clean(button.getAttribute('aria-label'));
          if (/^Session log$/i.test(text || label)) hide(button);
        }
        const settingsCandidates = [...document.querySelectorAll('button[aria-haspopup="dialog"]')];
        const settings = settingsCandidates.find(button =>
          /^(设置|Settings)$/i.test(
            clean(button.textContent)
              || clean(button.getAttribute('aria-label'))
              || clean(button.getAttribute('title'))
          )
        ) ?? settingsCandidates.at(-1);
        if (settings) hide(settings);
      };
      apply();
      window.__rabbisirNativeMenuOwnershipObserver?.disconnect();
      const observer = new MutationObserver(apply);
      observer.observe(document.documentElement, { childList: true, subtree: true });
      window.__rabbisirNativeMenuOwnershipObserver = observer;
      return true;
    })()
    """

  static func selectionScript(sessionID: String) -> String {
    let encoded = try? JSONSerialization.data(
      withJSONObject: sessionID,
      options: .fragmentsAllowed
    )
    let jsonID = encoded.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    return """
      (() => {
        const requestedID = \(jsonID);
        if (typeof requestedID !== 'string' || requestedID.length === 0) return false;
        const projection = globalThis.__DSH_NATIVE_CONVERSATION_PROJECTION__;
        if (!projection || typeof projection.openSession !== 'function') return false;
        return projection.openSession(requestedID);
      })()
      """
  }

  static let clearSelectionScript = """
    (() => {
      const projection = globalThis.__DSH_NATIVE_CONVERSATION_PROJECTION__;
      if (!projection || typeof projection.clearSelection !== 'function') return false;
      projection.clearSelection();
      return true;
    })()
    """

  static let newSessionActivationScript = """
    (() => {
      const clean = value => (value || '').replace(/\\s+/g, ' ').trim();
      const trigger = [...document.querySelectorAll('button[aria-label]')].find(button =>
        /^(新建会话|new session)$/i.test(clean(button.getAttribute('aria-label')))
      );
      if (!trigger || trigger.disabled) return false;
      trigger.click();
      return true;
    })()
    """

  static let settingsActivationScript = """
    new Promise(async nativeResolve => {
      const resolve = value => nativeResolve(Boolean(value));
      const clean = value => (value || '').replace(/\\s+/g, ' ').trim();
      const wait = milliseconds => new Promise(done => setTimeout(done, milliseconds));
      const candidates = [...document.querySelectorAll('button[aria-haspopup="dialog"]')];
      const trigger = candidates.find(button => /^(设置|settings)$/i.test(
        clean(button.textContent)
          || clean(button.getAttribute('aria-label'))
          || clean(button.getAttribute('title'))
      ))
        ?? candidates.at(-1);
      if (!trigger || trigger.disabled) { resolve(false); return; }
      trigger.click();
      for (let attempt = 0; attempt < 60; attempt += 1) {
        await wait(50);
        const dialog = document.querySelector('[role="dialog"][aria-modal="true"]');
        if (dialog) {
          const applyRabbisirPolicy = \(deepSeekOnlySettingsPolicy);
          applyRabbisirPolicy(dialog);
          resolve(true);
          return;
        }
      }
      resolve(false);
    })
    """

  static let sessionLogActivationScript = """
    new Promise(async nativeResolve => {
      const resolve = value => nativeResolve(Boolean(value));
      const clean = value => (value || '').replace(/\\s+/g, ' ').trim();
      const wait = milliseconds => new Promise(done => setTimeout(done, milliseconds));
      const sessionDialog = () => [...document.querySelectorAll('[role="dialog"]')].find(candidate =>
        /(Session|会话).*(download|export|下载|导出)|(download|export|下载|导出).*(Session|会话)/i
          .test(clean(candidate.textContent) || clean(candidate.getAttribute('aria-label')))
      );
      const dismissRuntimeFeedback = dialog => {
        dialog.style.setProperty('display', 'none', 'important');
        dialog.setAttribute('aria-hidden', 'true');
        const close = [...dialog.querySelectorAll('button')].find(button =>
          /^(关闭|Close)$/i.test(clean(button.textContent) || clean(button.getAttribute('aria-label')))
        );
        close?.click();
      };
      const trigger = [...document.querySelectorAll('button')].find(button =>
        /^(Session log|会话日志)$/i.test(
          clean(button.textContent) || clean(button.getAttribute('aria-label'))
        )
      );
      if (!trigger || trigger.disabled) { resolve(false); return; }
      trigger.click();
      for (let attempt = 0; attempt < 30; attempt += 1) {
        await wait(50);
        const dialog = sessionDialog();
        if (dialog) dismissRuntimeFeedback(dialog);
        if (dialog || trigger.getAttribute('aria-busy') === 'true') {
          resolve(true);
          return;
        }
      }
      resolve(false);
    })
    """
}
