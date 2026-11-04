// extension.js
// Native GNOME Shell extension of PYMEHackers Control Center.
//
// It places an icon in the top bar that opens the "PYMEHackers Control Center" menu with the
// "Systems" and "Cybersecurity" sections. Each section lists the installed modules (discovered from
// the registry /usr/share/pymehackers/modules/<section>/, .desktop manifests) and each module shows
// its actions in a submenu. The "Module catalog" submenu lists the modules published in the
// PHCC-modules repository and installs, updates, reinstalls or uninstalls them through the backend
// helper /usr/libexec/phcc/phcc-modules (run with pkexec for every change). It is the native
// equivalent of the MATE AppIndicator, so GNOME Shell does not depend on
// gnome-shell-extension-appindicator.
//
// Every visible text comes from the language files of the core
// (/usr/share/pymehackers/core/lang/<language>.json), shared with the AppIndicator.
//
// Compatible with GNOME 45+ (ESM modules). The names _init, enable, disable and destroy are
// required by the GNOME Shell API; everything else follows the project conventions
// (c/v/a/d/p prefixes and m* methods).

import GObject from 'gi://GObject';
import St from 'gi://St';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// Root directory of the module registry (the same one used by the MATE AppIndicator).
const cModulesRoot = '/usr/share/pymehackers/modules';

// Language files of the core and supported languages (alphabetical order; en-US is the default).
const cLangDir = '/usr/share/pymehackers/core/lang';
const aSupportedLanguages = ['en-GB', 'en-US', 'es-AR', 'es-ES'];
const cDefaultLanguage = 'en-US';

// Backend helper of the module catalog. pkexec only accepts this exact path (polkit policy).
const cModulesHelper = '/usr/libexec/phcc/phcc-modules';

// Exit codes of pkexec when the authorization dialog is dismissed or the authentication fails.
const cPkexecDismissed = 126;
const cPkexecNotAuthorized = 127;

// UUID of this extension. "Quit" hides the icon by disabling it with this identifier.
const cUuid = 'phcc@pymehackers.com';

// Platform sections: directory identifier and key of the visible label.
const aSections = [
  {vId: 'sys', vLabelKey: 'section.sys'},
  {vId: 'cs', vLabelKey: 'section.cs'},
];

// Maps a locale (es_AR.UTF-8, en, C...) to a supported language, or null.
function fMatchLanguage(pLocale) {
  let vTag = pLocale.replace(/[.@].*$/, '').replace('_', '-').toLowerCase();
  for (const vLanguage of aSupportedLanguages) {
    if (vLanguage.toLowerCase() === vTag)
      return vLanguage;
  }
  if (vTag === 'en' || vTag.startsWith('en-'))
    return 'en-US';
  if (vTag === 'es' || vTag.startsWith('es-'))
    return 'es-ES';
  return null;
}

// Reads a language file. Returns an empty object if it cannot be read or parsed.
function fLoadLanguageFile(pLanguage) {
  try {
    let [vOk, vBytes] = GLib.file_get_contents(GLib.build_filenamev([cLangDir, `${pLanguage}.json`]));
    if (!vOk)
      return {};
    let dTexts = JSON.parse(new TextDecoder().decode(vBytes));
    return (dTexts !== null && typeof dTexts === 'object') ? dTexts : {};
  } catch (vErr) {
    logError(vErr, `PYMEHackers Control Center: could not read the language file ${pLanguage}.json`);
    return {};
  }
}

// Translator of the extension: selected language with en-US fallback.
class Translator {
  constructor() {
    this.vLanguage = cDefaultLanguage;
    for (const vLocale of GLib.get_language_names()) {
      let vMatch = fMatchLanguage(vLocale);
      if (vMatch !== null) {
        this.vLanguage = vMatch;
        break;
      }
    }
    this.dFallback = fLoadLanguageFile(cDefaultLanguage);
    this.dSelected = this.vLanguage === cDefaultLanguage ? {} : fLoadLanguageFile(this.vLanguage);
  }

  // Text of a key; the arguments replace the placeholders {0}, {1}...
  mT(pKey, ...aArguments) {
    let vText = this.dSelected[pKey] ?? this.dFallback[pKey] ?? pKey;
    aArguments.forEach((vArgument, vIndex) => {
      vText = vText.split(`{${vIndex}}`).join(String(vArgument));
    });
    return vText;
  }
}

const PymeHackersIndicator = GObject.registerClass(
class PymeHackersIndicator extends PanelMenu.Button {
  // GObject constructor (the name _init is required by the GNOME Shell API).
  _init() {
    this.vTranslator = new Translator();
    super._init(0.0, this.vTranslator.mT('app.title'));

    this.vDestroyed = false;
    this.vCatalogState = 'loading';   // loading, ready or failed
    this.aCatalog = [];
    this.vBusy = false;

    this.add_child(new St.Icon({
      icon_name: 'phcc-symbolic',
      style_class: 'system-status-icon',
    }));

    this.mBuildMenu();
    this.mLoadCatalog(false);
  }

  // Destructor (the name destroy is required by the GNOME Shell API). Pending subprocess
  // callbacks check vDestroyed before touching the menu.
  destroy() {
    this.vDestroyed = true;
    super.destroy();
  }

  // Shortcut to the translator.
  mT(pKey, ...aArguments) {
    return this.vTranslator.mT(pKey, ...aArguments);
  }

  // Builds the root menu: header + one entry (submenu) per section + catalog + quit.
  mBuildMenu() {
    let vHeader = new PopupMenu.PopupMenuItem(this.mT('app.title'), {reactive: false});
    this.menu.addMenuItem(vHeader);
    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

    for (const vSection of aSections) {
      let vItem = new PopupMenu.PopupSubMenuMenuItem(this.mT(vSection.vLabelKey));
      this.mBuildSection(vItem.menu, vSection.vId);
      this.menu.addMenuItem(vItem);
    }

    // Catalog of the modules published in the PHCC-modules repository.
    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
    let vCatalogItem = new PopupMenu.PopupSubMenuMenuItem(this.mT('menu.catalog'));
    this.mBuildCatalog(vCatalogItem.menu);
    this.menu.addMenuItem(vCatalogItem);

    // Separator and "Quit" at the end of the menu (equivalent of the MATE AppIndicator "Quit").
    this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
    let vQuit = new PopupMenu.PopupMenuItem(this.mT('menu.quit'));
    vQuit.connect('activate', () => this.mQuit());
    this.menu.addMenuItem(vQuit);
  }

  // Rebuilds the whole menu (after loading the catalog or after a module operation).
  mRebuildMenu() {
    if (this.vDestroyed)
      return;
    this.menu.removeAll();
    this.mBuildMenu();
  }

  // Fills the submenu of a section with the modules discovered in its directory.
  mBuildSection(pMenu, pSectionId) {
    let aModules = this.mDiscoverModules(pSectionId);
    if (aModules.length === 0) {
      pMenu.addMenuItem(new PopupMenu.PopupMenuItem(this.mT('section.empty'), {reactive: false}));
      return;
    }
    for (const vMod of aModules) {
      // Like the AppIndicator: a module without actions is a plain item, not an empty submenu.
      let vModItem = vMod.aActions.length > 0
        ? new PopupMenu.PopupSubMenuMenuItem(vMod.vName) : new PopupMenu.PopupMenuItem(vMod.vName);
      for (const vAction of vMod.aActions) {
        let vActItem = new PopupMenu.PopupMenuItem(vAction.vName);
        vActItem.connect('activate', () => this.mSpawn(vAction.vExec));
        vModItem.menu.addMenuItem(vActItem);
      }
      pMenu.addMenuItem(vModItem);
    }
  }

  // Discovers and sorts (by X-PYMEHackers-Order and then by name) the modules of a section.
  mDiscoverModules(pSectionId) {
    let aResult = [];
    let vDir = Gio.File.new_for_path(GLib.build_filenamev([cModulesRoot, pSectionId]));
    let vEnum;
    try {
      vEnum = vDir.enumerate_children('standard::name', Gio.FileQueryInfoFlags.NONE, null);
    } catch (vErr) {
      return aResult; // the section directory does not exist
    }

    try {
      let vInfo;
      while ((vInfo = vEnum.next_file(null)) !== null) {
        let vName = vInfo.get_name();
        if (!vName.endsWith('.desktop'))
          continue;
        let vPath = GLib.build_filenamev([cModulesRoot, pSectionId, vName]);
        let vMod = this.mParseManifest(vPath);
        if (vMod !== null)
          aResult.push(vMod);
      }
    } catch (vErr) {
      Main.notifyError(this.mT('app.title'), this.mT('error.registry', vErr.message));
    } finally {
      try {
        vEnum.close(null);
      } catch (vErr) {
        logError(vErr, 'PYMEHackers Control Center: could not close the module registry');
      }
    }

    aResult.sort(
      (pA, pB) => (pA.vOrder - pB.vOrder) || pA.vName.localeCompare(pB.vName)
    );
    return aResult;
  }

  // Reads a manifest (.desktop) and returns its data, or null if it is not valid.
  mParseManifest(pPath) {
    let vKf = new GLib.KeyFile();
    try {
      vKf.load_from_file(pPath, GLib.KeyFileFlags.NONE);
    } catch (vErr) {
      return null;
    }

    let vName;
    try {
      // Honours the localized keys of the manifest (Name[es_ES]...).
      vName = vKf.get_locale_string('Desktop Entry', 'Name', null);
    } catch (vErr) {
      return null; // without Name the module cannot be shown
    }

    let vOrder = 1000; // without a declared Order: placed after the ordered modules
    try {
      vOrder = vKf.get_integer('Desktop Entry', 'X-PYMEHackers-Order');
    } catch (vErr) {
      // the default value is kept
    }

    let vActionsStr = '';
    try {
      vActionsStr = vKf.get_string('Desktop Entry', 'Actions');
    } catch (vErr) {
      vActionsStr = '';
    }

    let aActions = [];
    for (const vAct of vActionsStr.split(';')) {
      if (vAct === '')
        continue;
      let vGroup = `Desktop Action ${vAct}`;
      try {
        let vActName = vKf.get_locale_string(vGroup, 'Name', null);
        let vActExec = vKf.get_string(vGroup, 'Exec');
        aActions.push({vName: vActName, vExec: vActExec});
      } catch (vErr) {
        // Malformed action (no Name or Exec): ignored.
      }
    }

    return {vName: vName, vOrder: vOrder, aActions: aActions};
  }

  // Asks the backend helper for the module catalog in the background. pRefresh skips its cache.
  mLoadCatalog(pRefresh) {
    this.vCatalogState = 'loading';
    let aArgv = [cModulesHelper, 'list', '--lang', this.vTranslator.vLanguage];
    if (pRefresh)
      aArgv.push('--refresh');

    let vProcess;
    try {
      vProcess = Gio.Subprocess.new(
        aArgv,
        Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE
      );
    } catch (vErr) {
      logError(vErr, 'PYMEHackers Control Center: could not start the module helper');
      this.vCatalogState = 'failed';
      this.mRebuildMenu();
      return;
    }

    vProcess.communicate_utf8_async(null, null, (pProcess, pResult) => {
      if (this.vDestroyed)
        return;
      try {
        let [, vStdout] = pProcess.communicate_utf8_finish(pResult);
        if (!pProcess.get_successful())
          throw new Error('the helper returned an error');
        this.aCatalog = this.mParseCatalog(vStdout ?? '');
        this.vCatalogState = 'ready';
      } catch (vErr) {
        logError(vErr, 'PYMEHackers Control Center: could not list the module catalog');
        this.vCatalogState = 'failed';
      }
      this.mRebuildMenu();
    });
    this.mRebuildMenu();
  }

  // Parses the output of "phcc-modules list": one module per line, 7 tab-separated fields
  // (id, section, version, installed version, supported 0/1, name, description).
  mParseCatalog(pOutput) {
    let aEntries = [];
    for (const vLine of pOutput.split('\n')) {
      if (vLine === '')
        continue;
      let aFields = vLine.split('\t');
      if (aFields.length !== 7 || aFields[0] === '' || aFields[5] === '')
        continue;
      aEntries.push({
        vId: aFields[0],
        vSection: aFields[1],
        vVersion: aFields[2],
        vInstalledVersion: aFields[3],
        vSupported: aFields[4] === '1',
        vName: aFields[5],
        vDescription: aFields[6],
      });
    }
    // Systems before Cybersecurity, then by name.
    aEntries.sort((pA, pB) => {
      let vSectionA = pA.vSection === 'sys' ? 0 : 1;
      let vSectionB = pB.vSection === 'sys' ? 0 : 1;
      return (vSectionA - vSectionB) || pA.vName.localeCompare(pB.vName);
    });
    return aEntries;
  }

  // Fills the "Module catalog" submenu from the current catalog state.
  mBuildCatalog(pMenu) {
    let vStatusKey = null;
    if (this.vCatalogState === 'loading')
      vStatusKey = 'catalog.loading';
    else if (this.vCatalogState === 'failed')
      vStatusKey = 'catalog.error';
    else if (this.vBusy)
      vStatusKey = 'catalog.busy';
    if (vStatusKey !== null)
      pMenu.addMenuItem(new PopupMenu.PopupMenuItem(this.mT(vStatusKey), {reactive: false}));

    if (this.vCatalogState === 'ready') {
      if (this.aCatalog.length === 0)
        pMenu.addMenuItem(new PopupMenu.PopupMenuItem(this.mT('catalog.empty'), {reactive: false}));

      for (const vEntry of this.aCatalog) {
        let vInstalled = vEntry.vInstalledVersion !== '';
        if (!vEntry.vSupported) {
          pMenu.addMenuItem(new PopupMenu.PopupMenuItem(
            this.mT('catalog.unsupported', vEntry.vName), {reactive: false}));
          continue;
        }

        let vLabel = vInstalled
          ? this.mT('catalog.installed', vEntry.vName, vEntry.vInstalledVersion)
          : this.mT('catalog.available', vEntry.vName, vEntry.vVersion);
        let vItem = new PopupMenu.PopupSubMenuMenuItem(vLabel);

        if (vEntry.vDescription !== '') {
          vItem.menu.addMenuItem(new PopupMenu.PopupMenuItem(vEntry.vDescription, {reactive: false}));
          vItem.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        }
        if (!vInstalled) {
          this.mAddCatalogAction(vItem.menu, this.mT('action.install'), 'install', vEntry);
        } else {
          if (vEntry.vInstalledVersion !== vEntry.vVersion)
            this.mAddCatalogAction(vItem.menu, this.mT('action.update', vEntry.vVersion), 'update', vEntry);
          this.mAddCatalogAction(vItem.menu, this.mT('action.reinstall'), 'reinstall', vEntry);
          this.mAddCatalogAction(vItem.menu, this.mT('action.uninstall'), 'uninstall', vEntry);
        }
        pMenu.addMenuItem(vItem);
      }
    }

    pMenu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
    let vRefresh = new PopupMenu.PopupMenuItem(this.mT('catalog.refresh'));
    vRefresh.setSensitive(this.vCatalogState !== 'loading' && !this.vBusy);
    vRefresh.connect('activate', () => this.mLoadCatalog(true));
    pMenu.addMenuItem(vRefresh);
  }

  // Adds an action (install, update...) to the submenu of a catalog entry.
  mAddCatalogAction(pMenu, pLabel, pAction, pEntry) {
    let vItem = new PopupMenu.PopupMenuItem(pLabel);
    vItem.setSensitive(!this.vBusy);
    vItem.connect('activate', () => this.mRunOperation(pAction, pEntry));
    pMenu.addMenuItem(vItem);
  }

  // Runs "pkexec phcc-modules <action> <id>" in the background and notifies the result.
  mRunOperation(pAction, pEntry) {
    if (this.vBusy)
      return;

    let vProcess;
    try {
      vProcess = Gio.Subprocess.new(
        ['pkexec', cModulesHelper, pAction, pEntry.vId],
        Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE
      );
    } catch (vErr) {
      Main.notifyError(this.mT('app.title'), this.mT('error.spawn', 'pkexec', vErr.message));
      return;
    }

    Main.notify(this.mT('app.title'), this.mT(`notify.${pAction}`, pEntry.vName));
    this.vBusy = true;
    this.mRebuildMenu();

    vProcess.wait_async(null, (pProcess, pResult) => {
      let vKey = 'notify.failed';
      try {
        pProcess.wait_finish(pResult);
        if (pProcess.get_if_exited()) {
          let vStatus = pProcess.get_exit_status();
          if (vStatus === 0)
            vKey = 'notify.done';
          else if (vStatus === cPkexecDismissed || vStatus === cPkexecNotAuthorized)
            vKey = vStatus === cPkexecDismissed ? 'notify.cancelled' : 'notify.denied';
        }
      } catch (vErr) {
        logError(vErr, 'PYMEHackers Control Center: the module operation failed');
      }
      if (this.vDestroyed)
        return;
      Main.notify(this.mT('app.title'), this.mT(vKey, pEntry.vName));
      this.vBusy = false;
      this.mLoadCatalog(true);
    });
  }

  // Runs the command line of an action without blocking the Shell.
  mSpawn(pCommand) {
    try {
      GLib.spawn_command_line_async(pCommand);
    } catch (vErr) {
      Main.notifyError(this.mT('app.title'), this.mT('error.spawn', pCommand, vErr.message));
    }
  }

  // "Quit": hides the icon by disabling the extension. On GNOME there is no "process" to close as
  // with the AppIndicator; hiding the indicator means disabling the extension. The GNOME autostart
  // (phcc-gnome-activate.desktop) enables it again at the next login, just as the AppIndicator
  // starts again with the session on the other desktops.
  mQuit() {
    try {
      GLib.spawn_command_line_async(`gnome-extensions disable ${cUuid}`);
    } catch (vErr) {
      Main.notifyError(this.mT('app.title'), this.mT('error.quit'));
    }
  }
});

export default class PymeHackersExtension extends Extension {
  // Enables the extension: creates the indicator and adds it to the top bar.
  enable() {
    this.vIndicator = new PymeHackersIndicator();
    Main.panel.addToStatusArea(this.uuid, this.vIndicator);
  }

  // Disables the extension: destroys the indicator (it does not affect the module services).
  disable() {
    if (this.vIndicator !== null && this.vIndicator !== undefined)
      this.vIndicator.destroy();
    this.vIndicator = null;
  }
}
