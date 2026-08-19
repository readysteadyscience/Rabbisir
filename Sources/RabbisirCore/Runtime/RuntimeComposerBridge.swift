import Foundation

struct RuntimeComposerProjection: Equatable, Sendable {
  let workspace: String
  let agentPreset: String
  let modelAndReasoning: String
  let permission: String
  let isWorkspaceAvailable: Bool
  let isAgentPresetAvailable: Bool
  let isAvailable: Bool
  let canSubmit: Bool

  static var loading: RuntimeComposerProjection {
    loading(copy: RabbisirCopy(language: RabbisirInterfaceLanguage.currentPreference()))
  }

  static func loading(copy: RabbisirCopy) -> RuntimeComposerProjection {
    RuntimeComposerProjection(
      workspace: copy.composerLoadingWorkspace,
      agentPreset: copy.composerLoadingAgentPreset,
      modelAndReasoning: copy.composerLoadingModel,
      permission: copy.composerLoadingPermission,
      isWorkspaceAvailable: false,
      isAgentPresetAvailable: false,
      isAvailable: false,
      canSubmit: false
    )
  }

  static func decode(_ value: Any?) -> Self? {
    guard let fields = value as? [String: Any],
      let workspace = fields["workspace"] as? String,
      let agentPreset = fields["agentPreset"] as? String,
      let modelAndReasoning = fields["modelAndReasoning"] as? String,
      let permission = fields["permission"] as? String,
      let isWorkspaceAvailable = fields["isWorkspaceAvailable"] as? Bool,
      let isAgentPresetAvailable = fields["isAgentPresetAvailable"] as? Bool,
      let isAvailable = fields["isAvailable"] as? Bool,
      let canSubmit = fields["canSubmit"] as? Bool
    else {
      return nil
    }
    return RuntimeComposerProjection(
      workspace: workspace,
      agentPreset: agentPreset,
      modelAndReasoning: modelAndReasoning,
      permission: permission,
      isWorkspaceAvailable: isWorkspaceAvailable,
      isAgentPresetAvailable: isAgentPresetAvailable,
      isAvailable: isAvailable,
      canSubmit: canSubmit
    )
  }
}

struct RuntimeComposerOption: Equatable, Identifiable, Sendable {
  let id: String
  let label: String
  let detail: String?
  let isSelected: Bool

  static func decode(_ value: Any?) -> [Self]? {
    let decoded: Any?
    if let json = value as? String,
      let data = json.data(using: .utf8)
    {
      decoded = try? JSONSerialization.jsonObject(with: data)
    } else {
      decoded = value
    }
    guard let rows = decoded as? [[String: Any]] else { return nil }
    return rows.compactMap { row in
      guard let id = row["id"] as? String,
        let label = row["label"] as? String,
        let isSelected = row["isSelected"] as? Bool
      else {
        return nil
      }
      return RuntimeComposerOption(
        id: id,
        label: label,
        detail: row["detail"] as? String,
        isSelected: isSelected
      )
    }
  }
}

enum RuntimeComposerChoiceKind: String, CaseIterable, Sendable {
  case workspace
  case agentPreset
  case commands
  case permission
  case model
  case reasoning
}

struct RuntimeComposerSelectionResult: Sendable {
  let accepted: Bool
  let draft: String?
  let requiresUpstreamConfirmation: Bool

  static func decode(_ value: Any?) -> Self? {
    let decoded: Any?
    if let json = value as? String,
      let data = json.data(using: .utf8)
    {
      decoded = try? JSONSerialization.jsonObject(with: data)
    } else {
      decoded = value
    }
    guard let fields = decoded as? [String: Any],
      let accepted = fields["accepted"] as? Bool,
      let requiresUpstreamConfirmation = fields["requiresUpstreamConfirmation"] as? Bool
    else {
      return nil
    }
    return RuntimeComposerSelectionResult(
      accepted: accepted,
      draft: fields["draft"] as? String,
      requiresUpstreamConfirmation: requiresUpstreamConfirmation
    )
  }
}

struct RuntimeComposerSubmissionResult: Sendable {
  let accepted: Bool
  let stage: String

  static func decode(_ value: Any?) -> Self? {
    let decoded: Any?
    if let json = value as? String,
      let data = json.data(using: .utf8)
    {
      decoded = try? JSONSerialization.jsonObject(with: data)
    } else {
      decoded = value
    }
    guard let fields = decoded as? [String: Any],
      let accepted = fields["accepted"] as? Bool,
      let stage = fields["stage"] as? String
    else {
      return nil
    }
    return RuntimeComposerSubmissionResult(accepted: accepted, stage: stage)
  }
}

enum RuntimeComposerControl: String, Sendable {
  case commands
  case modelAndReasoning
  case permission
}

enum RuntimeComposerBridge {
  static let projectionScript = """
    (() => {
      const cards = [...document.querySelectorAll('[data-composer-card]')];
      const card = cards.find(candidate => {
        const input = candidate.querySelector('textarea');
        return input !== null && !input.disabled && input.getAttribute('aria-haspopup') !== 'menu';
      }) ?? cards.find(candidate => {
        const input = candidate.querySelector('textarea');
        return input !== null && input.getAttribute('aria-haspopup') !== 'menu';
      }) ?? cards.at(-1);
      const clean = (value, fallback) => {
        const normalized = (value || '').replace(/\\s+/g, ' ').trim();
        return normalized.length > 0 ? normalized : fallback;
      };
      if (!card) {
        return {
          workspace: '当前工作区',
          agentPreset: '仅新会话可选',
          modelAndReasoning: '会话模型',
          permission: '访问权限',
          isWorkspaceAvailable: false,
          isAgentPresetAvailable: false,
          isAvailable: false,
          canSubmit: false
        };
      }
      const textarea = card.querySelector('textarea');
      const buttons = [...card.querySelectorAll('button')];
      const primary = buttons.at(-1);
      const primaryLabel = clean(primary?.getAttribute('aria-label'), '');
      const sends = primaryLabel === '发送消息' || primaryLabel === 'Send message';
      const model = buttons.find((button) =>
        button.getAttribute('aria-haspopup') === 'menu'
          && clean(button.title, '').length > 0
      );
      const permission = buttons.find((button) => {
        const label = clean(button.getAttribute('aria-label'), '');
        return button !== model
          && clean(button.textContent, '').length > 0
          && /access|permission|权限|访问/i.test(label);
      });
      const workspace = [...document.querySelectorAll('button[aria-haspopup="menu"]')].find(button =>
        /choose workspace|选择工作区/i.test(clean(button.getAttribute('aria-label'), ''))
      );
      const agentPreset = [...document.querySelectorAll('button[aria-haspopup="menu"]')].find(button =>
        !button.closest('[data-composer-card]')
          && button !== workspace
          && clean(button.textContent, '').length > 0
      );
      return {
        workspace: clean(workspace?.textContent, '当前工作区'),
        agentPreset: clean(agentPreset?.textContent, '仅新会话可选'),
        modelAndReasoning: clean(model?.title, clean(model?.textContent, '会话模型')),
        permission: clean(permission?.textContent, '访问权限'),
        isWorkspaceAvailable: workspace !== undefined && !workspace.disabled,
        isAgentPresetAvailable: agentPreset !== undefined && !agentPreset.disabled,
        isAvailable: textarea !== null,
        canSubmit: textarea !== null && !textarea.disabled && !textarea.readOnly && sends
      };
    })()
    """

  static func activationScript(for control: RuntimeComposerControl) -> String {
    let targetName =
      switch control {
      case .commands:
        "commands"
      case .modelAndReasoning:
        "model"
      case .permission:
        "permission"
      }
    return """
      (() => {
        const cards = [...document.querySelectorAll('[data-composer-card]')];
        const card = cards.find(candidate => {
          const input = candidate.querySelector('textarea');
          return input !== null && !input.disabled && input.getAttribute('aria-haspopup') !== 'menu';
        }) ?? cards.find(candidate => {
          const input = candidate.querySelector('textarea');
          return input !== null && input.getAttribute('aria-haspopup') !== 'menu';
        }) ?? cards.at(-1);
        if (!card) return false;
        const clean = (value) => (value || '').replace(/\\s+/g, ' ').trim();
        const buttons = [...card.querySelectorAll('button')];
        const commands = buttons.find((button) =>
          button.getAttribute('aria-haspopup') === 'listbox'
        );
        const model = buttons.find((button) =>
          button.getAttribute('aria-haspopup') === 'menu'
            && clean(button.title).length > 0
        );
        const permission = buttons.find((button) => {
          const label = clean(button.getAttribute('aria-label'));
          return button !== model
            && clean(button.textContent).length > 0
            && /access|permission|权限|访问/i.test(label);
        });
        const target = \(targetName);
        if (!target || target.disabled) return false;
        target.scrollIntoView({ block: 'nearest', inline: 'nearest' });
        target.focus({ preventScroll: true });
        target.click();
        return true;
      })()
      """
  }

  static func choicesScript(for kind: RuntimeComposerChoiceKind) -> String {
    """
    new Promise(async (nativeResolve) => {
      const resolve = value => nativeResolve(JSON.stringify(value));
      const kind = '\(kind.rawValue)';
      const cards = [...document.querySelectorAll('[data-composer-card]')];
      const card = cards.find(candidate => {
        const input = candidate.querySelector('textarea');
        return input !== null && !input.disabled && input.getAttribute('aria-haspopup') !== 'menu';
      }) ?? cards.find(candidate => {
        const input = candidate.querySelector('textarea');
        return input !== null && input.getAttribute('aria-haspopup') !== 'menu';
      }) ?? cards.at(-1);
      if (!card) { resolve([]); return; }
      const clean = (value) => (value || '').replace(/\\s+/g, ' ').trim();
      const wait = (milliseconds = 70) => new Promise(done => setTimeout(done, milliseconds));
      const buttons = () => [...card.querySelectorAll('button')];
      const commands = () => buttons().find(button => button.getAttribute('aria-haspopup') === 'listbox');
      const model = () => buttons().find(button =>
        button.getAttribute('aria-haspopup') === 'menu' && clean(button.title).length > 0
      );
      const permission = () => buttons().find(button => {
        if (button === model() || button === commands() || button === buttons().at(-1)) return false;
        return clean(button.textContent).length > 0
          && /access|permission|权限|访问/i.test(clean(button.getAttribute('aria-label')));
      });
      const workspace = () => [...document.querySelectorAll('button[aria-haspopup="menu"]')].find(button =>
        /choose workspace|选择工作区/i.test(clean(button.getAttribute('aria-label')))
      );
      const agentPreset = () => [...document.querySelectorAll('button[aria-haspopup="menu"]')].find(button =>
        !button.closest('[data-composer-card]')
          && button !== workspace()
          && clean(button.textContent).length > 0
      );
      const menuInCard = (role) => [...card.querySelectorAll(`[role="${role}"]`)].at(-1);
      const copy = (button, prefix, index) => {
        const copyRoot = button.children[0];
        const label = clean(button.title)
          || clean(copyRoot?.children[0]?.textContent)
          || clean(copyRoot?.textContent)
          || clean(button.textContent)
          || clean(button.getAttribute('aria-label'))
          || `选项 ${index + 1}`;
        const detail = clean(copyRoot?.children[1]?.textContent);
        return {
          id: `${prefix}:${index}`,
          label,
          detail: detail.length > 0 && detail !== label ? detail : null,
          isSelected: button.getAttribute('aria-checked') === 'true'
            || button.getAttribute('aria-selected') === 'true'
        };
      };

      if (kind === 'workspace') {
        const trigger = workspace();
        if (!trigger || trigger.disabled) { resolve([]); return; }
        if (trigger.getAttribute('aria-expanded') === 'true') trigger.click();
        trigger.click();
        await wait();
        const current = clean(trigger.textContent);
        const menus = [...document.querySelectorAll('[role="menu"]')];
        const rows = [...menus.at(-1)?.querySelectorAll('[role="menuitem"]') || []];
        const result = rows.map((button, index) => {
          const option = copy(button, 'workspace', index);
          return { ...option, isSelected: option.label === current };
        });
        if (trigger.getAttribute('aria-expanded') === 'true') trigger.click();
        resolve(result);
        return;
      }

      if (kind === 'agentPreset') {
        const trigger = agentPreset();
        if (!trigger || trigger.disabled) { resolve([]); return; }
        if (trigger.getAttribute('aria-expanded') === 'true') trigger.click();
        trigger.click();
        await wait();
        const current = clean(trigger.textContent);
        const menus = [...document.querySelectorAll('[role="menu"]')];
        const rows = [...menus.at(-1)?.querySelectorAll('[role="menuitem"]') || []];
        const result = rows.map((button, index) => {
          const option = copy(button, 'agentPreset', index);
          return { ...option, isSelected: option.isSelected || option.label === current };
        });
        if (trigger.getAttribute('aria-expanded') === 'true') trigger.click();
        resolve(result);
        return;
      }

      if (kind === 'commands') {
        const trigger = commands();
        if (!trigger || trigger.disabled) { resolve([]); return; }
        if (trigger.getAttribute('aria-expanded') === 'true') trigger.click();
        trigger.click();
        await wait();
        const rows = [...card.querySelectorAll('[role="option"]')];
        const result = rows.map((button, index) => copy(button, 'commands', index));
        if (trigger.getAttribute('aria-expanded') === 'true') trigger.click();
        resolve(result);
        return;
      }

      if (kind === 'permission') {
        const trigger = permission();
        if (!trigger || trigger.disabled) { resolve([]); return; }
        trigger.click();
        await wait();
        const current = clean(trigger.textContent);
        const rows = [...menuInCard('menu')?.querySelectorAll('[role="menuitem"]') || []];
        const result = rows.map((button, index) => {
          const option = copy(button, 'permission', index);
          return { ...option, isSelected: option.isSelected || option.label === current };
        });
        trigger.click();
        resolve(result);
        return;
      }

      const trigger = model();
      if (!trigger || trigger.disabled) { resolve([]); return; }
      if (trigger.getAttribute('aria-expanded') === 'true') trigger.click();
      trigger.click();
      await wait();
      const controlledMenuID = trigger.getAttribute('aria-controls');
      const rootMenu = (controlledMenuID ? document.getElementById(controlledMenuID) : null)
        ?? menuInCard('menu');
      const rootRows = [...rootMenu?.querySelectorAll('button[role="menuitem"]') || []]
        .filter(button => button.closest('[role="menu"]') === rootMenu);
      const paneIndex = kind === 'model' ? 0 : 1;
      const pane = rootRows[paneIndex];
      if (!pane || pane.disabled) {
        trigger.click();
        resolve([]);
        return;
      }
      pane.click();
      let rows = [];
      for (let attempt = 0; attempt < 20 && rows.length === 0; attempt += 1) {
        await wait();
        rows = [...rootMenu.querySelectorAll('button[role="menuitemradio"]')];
      }
      const result = rows.map((button, index) => copy(button, kind, index));
      trigger.click();
      resolve(result);
    })
    """
  }

  static func selectionScript(
    kind: RuntimeComposerChoiceKind,
    optionID: String
  ) -> String {
    let encodedID = try? JSONSerialization.data(
      withJSONObject: optionID,
      options: .fragmentsAllowed
    )
    let jsonID = encodedID.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    return """
      new Promise(async (nativeResolve) => {
        const resolve = value => nativeResolve(JSON.stringify(value));
        const kind = '\(kind.rawValue)';
        const requestedID = \(jsonID);
        const index = Number.parseInt(requestedID.split(':').at(-1) || '', 10);
        const cards = [...document.querySelectorAll('[data-composer-card]')];
        const card = cards.find(candidate => {
          const input = candidate.querySelector('textarea');
          return input !== null && !input.disabled && input.getAttribute('aria-haspopup') !== 'menu';
        }) ?? cards.find(candidate => {
          const input = candidate.querySelector('textarea');
          return input !== null && input.getAttribute('aria-haspopup') !== 'menu';
        }) ?? cards.at(-1);
        const finish = (accepted, draft = null) => resolve({
          accepted,
          draft,
          requiresUpstreamConfirmation: document.querySelector('[role="dialog"]') !== null
        });
        if (!card || !Number.isInteger(index)) { finish(false); return; }
        const clean = (value) => (value || '').replace(/\\s+/g, ' ').trim();
        const wait = (milliseconds = 70) => new Promise(done => setTimeout(done, milliseconds));
        const buttons = () => [...card.querySelectorAll('button')];
        const commands = () => buttons().find(button => button.getAttribute('aria-haspopup') === 'listbox');
        const model = () => buttons().find(button =>
          button.getAttribute('aria-haspopup') === 'menu' && clean(button.title).length > 0
        );
        const permission = () => buttons().find(button => {
          if (button === model() || button === commands() || button === buttons().at(-1)) return false;
          return clean(button.textContent).length > 0
            && /access|permission|权限|访问/i.test(clean(button.getAttribute('aria-label')));
        });
        const workspace = () => [...document.querySelectorAll('button[aria-haspopup="menu"]')].find(button =>
          /choose workspace|选择工作区/i.test(clean(button.getAttribute('aria-label')))
        );
        const agentPreset = () => [...document.querySelectorAll('button[aria-haspopup="menu"]')].find(button =>
          !button.closest('[data-composer-card]')
            && button !== workspace()
            && clean(button.textContent).length > 0
        );
        const menuInCard = (role) => [...card.querySelectorAll(`[role="${role}"]`)].at(-1);
        const openMenuFor = trigger => {
          const controlledMenuID = trigger.getAttribute('aria-controls');
          const controlledMenu = controlledMenuID
            ? document.getElementById(controlledMenuID)
            : null;
          if (controlledMenu) return controlledMenu;
          const menus = [...document.querySelectorAll('[role="menu"]')];
          return menus.toReversed().find(menu => {
            const style = window.getComputedStyle(menu);
            return style.display !== 'none'
              && style.visibility !== 'hidden'
              && menu.getClientRects().length > 0;
          }) ?? null;
        };

        if (kind === 'workspace') {
          const trigger = workspace();
          if (!trigger || trigger.disabled) { finish(false); return; }
          if (trigger.getAttribute('aria-expanded') === 'true') trigger.click();
          trigger.click();
          await wait();
          const option = [...openMenuFor(trigger)?.querySelectorAll('[role="menuitem"]') || []][index];
          if (!option || option.disabled) { trigger.click(); finish(false); return; }
          option.click();
          await wait(110);
          finish(true);
          return;
        }

        if (kind === 'agentPreset') {
          const trigger = agentPreset();
          if (!trigger || trigger.disabled) { finish(false); return; }
          if (trigger.getAttribute('aria-expanded') === 'true') trigger.click();
          trigger.click();
          await wait();
          const menus = [...document.querySelectorAll('[role="menu"]')];
          const option = [...menus.at(-1)?.querySelectorAll('[role="menuitem"]') || []][index];
          if (!option || option.disabled) { trigger.click(); finish(false); return; }
          option.click();
          await wait(110);
          finish(true);
          return;
        }

        if (kind === 'commands') {
          const trigger = commands();
          if (!trigger || trigger.disabled) { finish(false); return; }
          if (trigger.getAttribute('aria-expanded') === 'true') trigger.click();
          trigger.click();
          await wait();
          const option = [...card.querySelectorAll('[role="option"]')][index];
          if (!option || option.disabled) { trigger.click(); finish(false); return; }
          option.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
          await wait();
          finish(true, card.querySelector('textarea')?.value ?? null);
          return;
        }

        if (kind === 'permission') {
          const trigger = permission();
          if (!trigger || trigger.disabled) { finish(false); return; }
          trigger.click();
          await wait();
          const option = [...menuInCard('menu')?.querySelectorAll('[role="menuitem"]') || []][index];
          if (!option || option.disabled) { trigger.click(); finish(false); return; }
          option.click();
          await wait();
          finish(true);
          return;
        }

        const trigger = model();
        if (!trigger || trigger.disabled) { finish(false); return; }
        if (trigger.getAttribute('aria-expanded') === 'true') trigger.click();
        trigger.click();
        await wait();
        const controlledMenuID = trigger.getAttribute('aria-controls');
        const rootMenu = (controlledMenuID ? document.getElementById(controlledMenuID) : null)
          ?? menuInCard('menu');
        const rootRows = [...rootMenu?.querySelectorAll('button[role="menuitem"]') || []]
          .filter(button => button.closest('[role="menu"]') === rootMenu);
        const pane = rootRows[kind === 'model' ? 0 : 1];
        if (!pane || pane.disabled) { trigger.click(); finish(false); return; }
        pane.click();
        let rows = [];
        for (let attempt = 0; attempt < 20 && rows.length === 0; attempt += 1) {
          await wait();
          rows = [...rootMenu.querySelectorAll('button[role="menuitemradio"]')];
        }
        const option = rows[index];
        if (!option || option.disabled) { trigger.click(); finish(false); return; }
        option.click();
        await wait(110);
        finish(true);
      })
      """
  }

  static func submissionScript(jsonText: String) -> String {
    """
    new Promise(async (nativeResolve) => {
      const resolve = (accepted, stage) => nativeResolve(JSON.stringify({ accepted, stage }));
      const wait = (milliseconds) => new Promise(done => setTimeout(done, milliseconds));
      const cards = [...document.querySelectorAll('[data-composer-card]')];
      const card = cards.find(candidate => {
        const input = candidate.querySelector('textarea');
        return input !== null && !input.disabled && input.getAttribute('aria-haspopup') !== 'menu';
      }) ?? cards.find(candidate => {
        const input = candidate.querySelector('textarea');
        return input !== null && input.getAttribute('aria-haspopup') !== 'menu';
      }) ?? cards.at(-1);
      const input = card?.querySelector('textarea');
      if (!input || input.disabled || input.readOnly) {
        resolve(false, 'composer-unavailable');
        return;
      }
      const setter = Object.getOwnPropertyDescriptor(
        HTMLTextAreaElement.prototype,
        'value'
      )?.set;
      if (!setter) {
        resolve(false, 'textarea-setter-unavailable');
        return;
      }
      const initialURL = location.href;
      setter.call(input, \(jsonText));
      input.dispatchEvent(new InputEvent('input', {
        bubbles: true,
        inputType: 'insertText',
        data: \(jsonText)
      }));
      for (let attempt = 0; attempt < 20; attempt += 1) {
        const buttons = [...card.querySelectorAll('button')];
        const primary = buttons.at(-1);
        const label = (primary?.getAttribute('aria-label') || '').trim();
        const sends = label === '发送消息' || label === 'Send message';
        if (primary && !primary.disabled && sends) {
          primary.click();
          for (let transition = 0; transition < 60; transition += 1) {
            await wait(50);
            const liveInput = card.querySelector('textarea');
            const livePrimary = [...card.querySelectorAll('button')].at(-1);
            const liveLabel = (livePrimary?.getAttribute('aria-label') || '').trim();
            if (location.href !== initialURL) {
              resolve(true, 'location-changed');
              return;
            }
            if (liveInput?.value === '') {
              resolve(true, 'composer-cleared');
              return;
            }
            if (liveLabel === '停止生成' || liveLabel === 'Stop generating') {
              resolve(true, 'generation-started');
              return;
            }
          }
          resolve(false, 'no-runtime-transition');
          return;
        }
        await wait(25);
      }
      resolve(false, 'send-action-unavailable');
    })
    """
  }

  static let visualExtractionScript = """
    (() => {
      const styleID = 'rabbisir-native-composer-extraction';
      if (document.getElementById(styleID)) return;
      const style = document.createElement('style');
      style.id = styleID;
      style.textContent = `
        [data-composer-card] {
          display: none !important;
        }
      `;
      (document.head || document.documentElement).appendChild(style);
    })()
    """
}
