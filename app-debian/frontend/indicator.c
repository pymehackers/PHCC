// indicator.c
// PYMEHackers Control Center top bar indicator for Debian (MATE and every other desktop with
// AppIndicator support). It places an icon in the top bar; clicking it opens the
// "PYMEHackers Control Center" menu with the "Systems" and "Cybersecurity" sections. Each section
// lists the installed modules (discovered from the registry /usr/share/pymehackers/modules/<section>/)
// and each module shows its configuration actions in a submenu.
//
// The "Module catalog" submenu lists the modules published in the PHCC-modules repository
// (https://github.com/pymehackers/PHCC-modules) and installs, updates, reinstalls or uninstalls
// them. The repository work is done by the backend helper /usr/libexec/phcc/phcc-modules: listing
// runs as the user, and every change runs as root through pkexec.
//
// Discovery is dynamic: each module installs a manifest (Desktop Entry format with Desktop Actions
// and X-PYMEHackers-* fields). Adding a module never requires touching this code.
//
// Every visible text comes from the language files (see i18n.h).
//
// Build: see app-debian/build/Makefile (gtk+-3.0 + ayatana-appindicator3-0.1).

#include <gtk/gtk.h>
#include <libayatana-appindicator/app-indicator.h>

#include "i18n.h"

// Root directory of the module registry.
#define cModulesRoot "/usr/share/pymehackers/modules"

// Backend helper that lists and installs the modules of the PHCC-modules repository. It must be
// this exact path: the polkit policy only lets pkexec run it from here.
#define cModulesHelper "/usr/libexec/phcc/phcc-modules"

// Exit codes of pkexec when the authorization dialog is dismissed or the authentication fails.
#define cPkexecDismissed 126
#define cPkexecNotAuthorized 127

// Platform sections: directory identifier and key of its visible label.
typedef struct {
  const char *vId;
  const char *vLabelKey;
} Section;

static const Section aSections[] = {
  { "sys", "section.sys" },
  { "cs",  "section.cs" }
};

// One module of the PHCC-modules repository, as reported by "phcc-modules list".
typedef struct {
  gchar *vId;
  gchar *vSection;
  gchar *vVersion;
  gchar *vInstalledVersion;   // empty when the module is not installed
  gboolean vSupported;        // FALSE when the module has no installer for this platform
  gchar *vName;
  gchar *vDescription;
} CatalogEntry;

// State of the module catalog.
typedef enum {
  cCatalogStateLoading,
  cCatalogStateReady,
  cCatalogStateFailed
} CatalogState;

typedef struct {
  CatalogState vState;
  GPtrArray *lEntries;        // CatalogEntry*, sorted by section and name
  gboolean vBusy;             // TRUE while an install/update/reinstall/uninstall is running
} Catalog;

// A module operation requested from the catalog menu.
typedef struct {
  gchar *vAction;             // install, update, reinstall or uninstall
  gchar *vId;
  gchar *vName;
} Operation;

static AppIndicator *vIndicator = NULL;
static Catalog vCatalog = { cCatalogStateLoading, NULL, FALSE };

static void fRefreshMenu(void);
static void fLoadCatalog(gboolean pRefresh);

// Shows a desktop notification (notify-send, from libnotify-bin). Without notify-send the message
// only goes to the session log.
static void fNotify(const char *pMessage) {
  g_message("PYMEHackers: %s", pMessage);
  gchar *vNotifySend = g_find_program_in_path("notify-send");
  if (vNotifySend == NULL)
    return;

  const gchar *aArgv[] = {
    vNotifySend, "-a", fT("app.title"), "-i", "phcc", fT("app.title"), pMessage, NULL
  };
  GError *vError = NULL;
  if (!g_spawn_async(NULL, (gchar **)aArgv, NULL, G_SPAWN_DEFAULT, NULL, NULL, NULL, &vError)) {
    g_warning("PYMEHackers: could not show a notification: %s",
              vError != NULL ? vError->message : "unknown error");
    if (vError != NULL)
      g_error_free(vError);
  }
  g_free(vNotifySend);
}

// Frees the Exec attached to a menu item when the item is destroyed.
// It has the GClosureNotify signature so no function pointer cast is needed.
static void fFreeActionData(gpointer pData, GClosure *pClosure) {
  (void)pClosure;
  g_free(pData);
}

// Runs a command line (the Exec of a manifest action) without blocking.
static void fOnActionActivate(GtkMenuItem *pItem, gpointer pData) {
  (void)pItem;
  const char *vCommand = (const char *)pData;
  GError *vError = NULL;
  if (!g_spawn_command_line_async(vCommand, &vError)) {
    gchar *vMessage = fTf("error.spawn", vCommand,
                          vError != NULL ? vError->message : "unknown error", NULL);
    g_warning("PYMEHackers: %s", vMessage);
    g_free(vMessage);
    if (vError != NULL)
      g_error_free(vError);
  }
}

// Builds the action submenu of a module from its manifest (GKeyFile already loaded).
// Returns a GtkMenu, or NULL if the module declares no actions.
static GtkWidget *fBuildModuleActions(GKeyFile *pKeyFile) {
  gchar *vActions = g_key_file_get_string(pKeyFile, "Desktop Entry", "Actions", NULL);
  if (vActions == NULL)
    return NULL;

  GtkWidget *vMenu = gtk_menu_new();
  gchar **aActionIds = g_strsplit(vActions, ";", -1);
  for (int vIndex = 0; aActionIds[vIndex] != NULL; vIndex++) {
    if (aActionIds[vIndex][0] == '\0')
      continue;
    gchar *vGroup = g_strdup_printf("Desktop Action %s", aActionIds[vIndex]);
    // Name honours the localized keys of the manifest (Name[es_ES]...); Exec is never localized.
    gchar *vName = g_key_file_get_locale_string(pKeyFile, vGroup, "Name", NULL, NULL);
    gchar *vExec = g_key_file_get_string(pKeyFile, vGroup, "Exec", NULL);
    if (vName != NULL && vExec != NULL) {
      GtkWidget *vItem = gtk_menu_item_new_with_label(vName);
      // The Exec is attached to the item and freed when the item is destroyed.
      g_signal_connect_data(vItem, "activate", G_CALLBACK(fOnActionActivate),
                            g_strdup(vExec), fFreeActionData, 0);
      gtk_menu_shell_append(GTK_MENU_SHELL(vMenu), vItem);
    }
    g_free(vName);
    g_free(vExec);
    g_free(vGroup);
  }
  g_strfreev(aActionIds);
  g_free(vActions);
  return vMenu;
}

// Data of a discovered module, needed to sort it and to build its menu entry.
typedef struct {
  int vOrder;            // value of X-PYMEHackers-Order (lower = shown first)
  gchar *vName;          // value of Name (visible label, localized when the manifest allows it)
  GKeyFile *vKeyFile;    // loaded manifest (reused to build the actions)
} ModuleInfo;

// Frees a ModuleInfo (used as the GDestroyNotify of the module GPtrArray).
static void fFreeModuleInfo(gpointer pData) {
  ModuleInfo *vInfo = (ModuleInfo *)pData;
  g_free(vInfo->vName);
  g_key_file_free(vInfo->vKeyFile);
  g_free(vInfo);
}

// Comparator: sorts the modules by X-PYMEHackers-Order and, when equal, by name.
// It receives pointers to the GPtrArray elements (that is, ModuleInfo**).
static gint fCompareModules(gconstpointer pA, gconstpointer pB) {
  const ModuleInfo *vA = *(const ModuleInfo **)pA;
  const ModuleInfo *vB = *(const ModuleInfo **)pB;
  if (vA->vOrder < vB->vOrder)
    return -1;
  if (vA->vOrder > vB->vOrder)
    return 1;
  return g_strcmp0(vA->vName, vB->vName);
}

// Fills the submenu of a section by discovering the modules of its registry directory.
// Returns the number of modules added.
static int fBuildSectionMenu(GtkWidget *pSectionMenu, const char *pSectionId) {
  gchar *vDirPath = g_strdup_printf("%s/%s", cModulesRoot, pSectionId);
  GDir *vDir = g_dir_open(vDirPath, 0, NULL);
  int vCount = 0;

  if (vDir != NULL) {
    // Load every manifest first so they can be sorted by their Order field.
    GPtrArray *lModules = g_ptr_array_new_with_free_func(fFreeModuleInfo);
    const gchar *vName;
    while ((vName = g_dir_read_name(vDir)) != NULL) {
      if (!g_str_has_suffix(vName, ".desktop"))
        continue;
      gchar *vPath = g_strdup_printf("%s/%s", vDirPath, vName);
      GKeyFile *vKf = g_key_file_new();
      if (g_key_file_load_from_file(vKf, vPath, G_KEY_FILE_NONE, NULL)) {
        gchar *vModName = g_key_file_get_locale_string(vKf, "Desktop Entry", "Name", NULL, NULL);
        if (vModName != NULL) {
          ModuleInfo *vInfo = g_new0(ModuleInfo, 1);
          vInfo->vName = vModName;
          vInfo->vKeyFile = vKf;
          // If the manifest declares no Order, place it after the ordered ones.
          GError *vErr = NULL;
          vInfo->vOrder = g_key_file_get_integer(
            vKf, "Desktop Entry", "X-PYMEHackers-Order", &vErr);
          if (vErr != NULL) {
            vInfo->vOrder = 1000;
            g_error_free(vErr);
          }
          g_ptr_array_add(lModules, vInfo);
        } else {
          g_key_file_free(vKf);
        }
      } else {
        g_key_file_free(vKf);
      }
      g_free(vPath);
    }
    g_ptr_array_sort(lModules, fCompareModules);

    for (guint vIndex = 0; vIndex < lModules->len; vIndex++) {
      ModuleInfo *vInfo = (ModuleInfo *)lModules->pdata[vIndex];
      GtkWidget *vModItem = gtk_menu_item_new_with_label(vInfo->vName);
      GtkWidget *vActions = fBuildModuleActions(vInfo->vKeyFile);
      if (vActions != NULL)
        gtk_menu_item_set_submenu(GTK_MENU_ITEM(vModItem), vActions);
      gtk_menu_shell_append(GTK_MENU_SHELL(pSectionMenu), vModItem);
      vCount++;
    }
    g_ptr_array_free(lModules, TRUE);
    g_dir_close(vDir);
  }

  // If the section has no modules, show a disabled informative item.
  if (vCount == 0) {
    GtkWidget *vEmpty = gtk_menu_item_new_with_label(fT("section.empty"));
    gtk_widget_set_sensitive(vEmpty, FALSE);
    gtk_menu_shell_append(GTK_MENU_SHELL(pSectionMenu), vEmpty);
  }

  g_free(vDirPath);
  return vCount;
}

// Frees a CatalogEntry (GDestroyNotify of the catalog GPtrArray).
static void fFreeCatalogEntry(gpointer pData) {
  CatalogEntry *vEntry = (CatalogEntry *)pData;
  g_free(vEntry->vId);
  g_free(vEntry->vSection);
  g_free(vEntry->vVersion);
  g_free(vEntry->vInstalledVersion);
  g_free(vEntry->vName);
  g_free(vEntry->vDescription);
  g_free(vEntry);
}

// Comparator of catalog entries: Systems before Cybersecurity, then by name.
static gint fCompareCatalogEntries(gconstpointer pA, gconstpointer pB) {
  const CatalogEntry *vA = *(const CatalogEntry **)pA;
  const CatalogEntry *vB = *(const CatalogEntry **)pB;
  int vSectionA = g_strcmp0(vA->vSection, "sys") == 0 ? 0 : 1;
  int vSectionB = g_strcmp0(vB->vSection, "sys") == 0 ? 0 : 1;
  if (vSectionA != vSectionB)
    return vSectionA - vSectionB;
  return g_utf8_collate(vA->vName, vB->vName);
}

// Parses the output of "phcc-modules list": one module per line, 7 tab-separated fields
// (id, section, version, installed version, supported 0/1, name, description).
// Malformed lines are ignored.
static GPtrArray *fParseCatalog(const gchar *pOutput) {
  GPtrArray *lEntries = g_ptr_array_new_with_free_func(fFreeCatalogEntry);
  gchar **aLines = g_strsplit(pOutput != NULL ? pOutput : "", "\n", -1);
  for (int vIndex = 0; aLines[vIndex] != NULL; vIndex++) {
    if (aLines[vIndex][0] == '\0')
      continue;
    gchar **aFields = g_strsplit(aLines[vIndex], "\t", 7);
    if (g_strv_length(aFields) == 7 && aFields[0][0] != '\0' && aFields[5][0] != '\0'
        && g_utf8_validate(aLines[vIndex], -1, NULL)) {
      CatalogEntry *vEntry = g_new0(CatalogEntry, 1);
      vEntry->vId = g_strdup(aFields[0]);
      vEntry->vSection = g_strdup(aFields[1]);
      vEntry->vVersion = g_strdup(aFields[2]);
      vEntry->vInstalledVersion = g_strdup(aFields[3]);
      vEntry->vSupported = g_strcmp0(aFields[4], "1") == 0;
      vEntry->vName = g_strdup(aFields[5]);
      vEntry->vDescription = g_strdup(aFields[6]);
      g_ptr_array_add(lEntries, vEntry);
    }
    g_strfreev(aFields);
  }
  g_strfreev(aLines);
  g_ptr_array_sort(lEntries, fCompareCatalogEntries);
  return lEntries;
}

// End of "phcc-modules list": stores the catalog and rebuilds the menu.
static void fOnCatalogListed(GObject *pSource, GAsyncResult *pResult, gpointer pData) {
  (void)pData;
  GSubprocess *vProcess = G_SUBPROCESS(pSource);
  gchar *vOutput = NULL;
  GError *vError = NULL;

  if (g_subprocess_communicate_utf8_finish(vProcess, pResult, &vOutput, NULL, &vError)
      && g_subprocess_get_if_exited(vProcess) && g_subprocess_get_exit_status(vProcess) == 0) {
    if (vCatalog.lEntries != NULL)
      g_ptr_array_free(vCatalog.lEntries, TRUE);
    vCatalog.lEntries = fParseCatalog(vOutput);
    vCatalog.vState = cCatalogStateReady;
  } else {
    g_warning("PYMEHackers: could not list the module catalog: %s",
              vError != NULL ? vError->message : "the helper returned an error");
    vCatalog.vState = cCatalogStateFailed;
  }

  if (vError != NULL)
    g_error_free(vError);
  g_free(vOutput);
  g_object_unref(vProcess);
  fRefreshMenu();
}

// Asks the backend helper for the catalog in the background. pRefresh skips its cache.
static void fLoadCatalog(gboolean pRefresh) {
  vCatalog.vState = cCatalogStateLoading;

  if (!g_file_test(cModulesHelper, G_FILE_TEST_IS_EXECUTABLE)) {
    g_warning("PYMEHackers: the module helper %s is missing", cModulesHelper);
    vCatalog.vState = cCatalogStateFailed;
    fRefreshMenu();
    return;
  }

  GError *vError = NULL;
  GSubprocess *vProcess = g_subprocess_new(
    G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_SILENCE, &vError,
    cModulesHelper, "list", "--lang", fI18nLanguage(), pRefresh ? "--refresh" : NULL, NULL);
  if (vProcess == NULL) {
    g_warning("PYMEHackers: could not start %s: %s", cModulesHelper,
              vError != NULL ? vError->message : "unknown error");
    if (vError != NULL)
      g_error_free(vError);
    vCatalog.vState = cCatalogStateFailed;
    fRefreshMenu();
    return;
  }

  g_subprocess_communicate_utf8_async(vProcess, NULL, NULL, fOnCatalogListed, NULL);
  fRefreshMenu();
}

// "Refresh catalog" menu item.
static void fOnCatalogRefreshActivate(GtkMenuItem *pItem, gpointer pData) {
  (void)pItem;
  (void)pData;
  fLoadCatalog(TRUE);
}

// Frees an Operation (also used as the GClosureNotify of the catalog action items).
static void fFreeOperation(gpointer pData) {
  Operation *vOperation = (Operation *)pData;
  if (vOperation == NULL)
    return;
  g_free(vOperation->vAction);
  g_free(vOperation->vId);
  g_free(vOperation->vName);
  g_free(vOperation);
}

static void fFreeOperationClosure(gpointer pData, GClosure *pClosure) {
  (void)pClosure;
  fFreeOperation(pData);
}

// End of a module operation: notifies the result and reloads the catalog and the menu (a new
// module brings a new manifest to the registry, an uninstalled one takes it away).
static void fOnOperationFinished(GObject *pSource, GAsyncResult *pResult, gpointer pData) {
  GSubprocess *vProcess = G_SUBPROCESS(pSource);
  Operation *vOperation = (Operation *)pData;
  GError *vError = NULL;
  const char *vKey = "notify.failed";

  if (g_subprocess_wait_finish(vProcess, pResult, &vError) && g_subprocess_get_if_exited(vProcess)) {
    int vStatus = g_subprocess_get_exit_status(vProcess);
    if (vStatus == 0)
      vKey = "notify.done";
    else if (vStatus == cPkexecDismissed || vStatus == cPkexecNotAuthorized)
      vKey = vStatus == cPkexecDismissed ? "notify.cancelled" : "notify.denied";
  }
  if (vError != NULL)
    g_error_free(vError);

  gchar *vMessage = fTf(vKey, vOperation->vName, NULL);
  fNotify(vMessage);
  g_free(vMessage);

  vCatalog.vBusy = FALSE;
  fFreeOperation(vOperation);
  g_object_unref(vProcess);
  fLoadCatalog(TRUE);
}

// Catalog action item: runs "pkexec phcc-modules <action> <id>" in the background.
static void fOnCatalogActionActivate(GtkMenuItem *pItem, gpointer pData) {
  (void)pItem;
  const Operation *vRequested = (const Operation *)pData;
  if (vCatalog.vBusy)
    return;

  Operation *vOperation = g_new0(Operation, 1);
  vOperation->vAction = g_strdup(vRequested->vAction);
  vOperation->vId = g_strdup(vRequested->vId);
  vOperation->vName = g_strdup(vRequested->vName);

  GError *vError = NULL;
  GSubprocess *vProcess = g_subprocess_new(
    G_SUBPROCESS_FLAGS_STDOUT_SILENCE | G_SUBPROCESS_FLAGS_STDERR_SILENCE, &vError,
    "pkexec", cModulesHelper, vOperation->vAction, vOperation->vId, NULL);
  if (vProcess == NULL) {
    gchar *vMessage = fTf("error.spawn", "pkexec",
                          vError != NULL ? vError->message : "unknown error", NULL);
    fNotify(vMessage);
    g_free(vMessage);
    if (vError != NULL)
      g_error_free(vError);
    fFreeOperation(vOperation);
    return;
  }

  gchar *vKey = g_strdup_printf("notify.%s", vOperation->vAction);
  gchar *vMessage = fTf(vKey, vOperation->vName, NULL);
  fNotify(vMessage);
  g_free(vMessage);
  g_free(vKey);

  vCatalog.vBusy = TRUE;
  g_subprocess_wait_async(vProcess, NULL, fOnOperationFinished, vOperation);
  fRefreshMenu();
}

// Adds one action item (install, update...) to the submenu of a catalog entry.
static void fAppendCatalogAction(GtkWidget *pMenu, const char *pLabel, const char *pAction,
                                 const CatalogEntry *pEntry) {
  Operation *vOperation = g_new0(Operation, 1);
  vOperation->vAction = g_strdup(pAction);
  vOperation->vId = g_strdup(pEntry->vId);
  vOperation->vName = g_strdup(pEntry->vName);

  GtkWidget *vItem = gtk_menu_item_new_with_label(pLabel);
  g_signal_connect_data(vItem, "activate", G_CALLBACK(fOnCatalogActionActivate),
                        vOperation, fFreeOperationClosure, 0);
  gtk_widget_set_sensitive(vItem, !vCatalog.vBusy);
  gtk_menu_shell_append(GTK_MENU_SHELL(pMenu), vItem);
}

// Builds the "Module catalog" submenu from the current catalog state.
static GtkWidget *fBuildCatalogMenu(void) {
  GtkWidget *vMenu = gtk_menu_new();
  const char *vStatusKey = NULL;

  if (vCatalog.vState == cCatalogStateLoading)
    vStatusKey = "catalog.loading";
  else if (vCatalog.vState == cCatalogStateFailed)
    vStatusKey = "catalog.error";
  else if (vCatalog.vBusy)
    vStatusKey = "catalog.busy";

  if (vStatusKey != NULL) {
    GtkWidget *vStatus = gtk_menu_item_new_with_label(fT(vStatusKey));
    gtk_widget_set_sensitive(vStatus, FALSE);
    gtk_menu_shell_append(GTK_MENU_SHELL(vMenu), vStatus);
  }

  if (vCatalog.vState == cCatalogStateReady) {
    if (vCatalog.lEntries == NULL || vCatalog.lEntries->len == 0) {
      GtkWidget *vEmpty = gtk_menu_item_new_with_label(fT("catalog.empty"));
      gtk_widget_set_sensitive(vEmpty, FALSE);
      gtk_menu_shell_append(GTK_MENU_SHELL(vMenu), vEmpty);
    } else {
      if (vCatalog.vBusy)
        gtk_menu_shell_append(GTK_MENU_SHELL(vMenu), gtk_separator_menu_item_new());
      for (guint vIndex = 0; vIndex < vCatalog.lEntries->len; vIndex++) {
        const CatalogEntry *vEntry = (const CatalogEntry *)vCatalog.lEntries->pdata[vIndex];
        gboolean vInstalled = vEntry->vInstalledVersion[0] != '\0';
        gchar *vLabel;

        if (!vEntry->vSupported)
          vLabel = fTf("catalog.unsupported", vEntry->vName, NULL);
        else if (vInstalled)
          vLabel = fTf("catalog.installed", vEntry->vName, vEntry->vInstalledVersion, NULL);
        else
          vLabel = fTf("catalog.available", vEntry->vName, vEntry->vVersion, NULL);

        GtkWidget *vItem = gtk_menu_item_new_with_label(vLabel);
        g_free(vLabel);
        gtk_menu_shell_append(GTK_MENU_SHELL(vMenu), vItem);
        if (!vEntry->vSupported) {
          gtk_widget_set_sensitive(vItem, FALSE);
          continue;
        }

        // Submenu of the module: description (informative) and the available actions.
        GtkWidget *vActions = gtk_menu_new();
        if (vEntry->vDescription[0] != '\0') {
          GtkWidget *vDescription = gtk_menu_item_new_with_label(vEntry->vDescription);
          gtk_widget_set_sensitive(vDescription, FALSE);
          gtk_menu_shell_append(GTK_MENU_SHELL(vActions), vDescription);
          gtk_menu_shell_append(GTK_MENU_SHELL(vActions), gtk_separator_menu_item_new());
        }
        if (!vInstalled) {
          fAppendCatalogAction(vActions, fT("action.install"), "install", vEntry);
        } else {
          if (g_strcmp0(vEntry->vInstalledVersion, vEntry->vVersion) != 0) {
            gchar *vUpdate = fTf("action.update", vEntry->vVersion, NULL);
            fAppendCatalogAction(vActions, vUpdate, "update", vEntry);
            g_free(vUpdate);
          }
          fAppendCatalogAction(vActions, fT("action.reinstall"), "reinstall", vEntry);
          fAppendCatalogAction(vActions, fT("action.uninstall"), "uninstall", vEntry);
        }
        gtk_menu_item_set_submenu(GTK_MENU_ITEM(vItem), vActions);
      }
    }
  }

  gtk_menu_shell_append(GTK_MENU_SHELL(vMenu), gtk_separator_menu_item_new());
  GtkWidget *vRefresh = gtk_menu_item_new_with_label(fT("catalog.refresh"));
  g_signal_connect(vRefresh, "activate", G_CALLBACK(fOnCatalogRefreshActivate), NULL);
  gtk_widget_set_sensitive(vRefresh,
                           vCatalog.vState != cCatalogStateLoading && !vCatalog.vBusy);
  gtk_menu_shell_append(GTK_MENU_SHELL(vMenu), vRefresh);

  return vMenu;
}

// Builds the complete root menu of the platform.
static GtkWidget *fBuildMenu(void) {
  GtkWidget *vMenu = gtk_menu_new();

  // "PYMEHackers" header (disabled, used as a title).
  GtkWidget *vHeader = gtk_menu_item_new_with_label(fT("menu.header"));
  gtk_widget_set_sensitive(vHeader, FALSE);
  gtk_menu_shell_append(GTK_MENU_SHELL(vMenu), vHeader);
  gtk_menu_shell_append(GTK_MENU_SHELL(vMenu), gtk_separator_menu_item_new());

  // One entry per section, each with its submenu of modules.
  for (size_t vIndex = 0; vIndex < sizeof(aSections) / sizeof(aSections[0]); vIndex++) {
    GtkWidget *vSectionItem = gtk_menu_item_new_with_label(fT(aSections[vIndex].vLabelKey));
    GtkWidget *vSectionMenu = gtk_menu_new();
    fBuildSectionMenu(vSectionMenu, aSections[vIndex].vId);
    gtk_menu_item_set_submenu(GTK_MENU_ITEM(vSectionItem), vSectionMenu);
    gtk_menu_shell_append(GTK_MENU_SHELL(vMenu), vSectionItem);
  }

  gtk_menu_shell_append(GTK_MENU_SHELL(vMenu), gtk_separator_menu_item_new());

  // Catalog of the modules published in the PHCC-modules repository.
  GtkWidget *vCatalogItem = gtk_menu_item_new_with_label(fT("menu.catalog"));
  gtk_menu_item_set_submenu(GTK_MENU_ITEM(vCatalogItem), fBuildCatalogMenu());
  gtk_menu_shell_append(GTK_MENU_SHELL(vMenu), vCatalogItem);

  gtk_menu_shell_append(GTK_MENU_SHELL(vMenu), gtk_separator_menu_item_new());

  // Quit the indicator (it does not affect the module services, which keep running).
  GtkWidget *vQuit = gtk_menu_item_new_with_label(fT("menu.quit"));
  g_signal_connect(vQuit, "activate", G_CALLBACK(gtk_main_quit), NULL);
  gtk_menu_shell_append(GTK_MENU_SHELL(vMenu), vQuit);

  gtk_widget_show_all(vMenu);
  return vMenu;
}

// Rebuilds the whole menu (sections and catalog) and hands it to the indicator.
static void fRefreshMenu(void) {
  if (vIndicator == NULL)
    return;
  app_indicator_set_menu(vIndicator, GTK_MENU(fBuildMenu()));
}

int main(int pArgc, char **pArgv) {
  gtk_init(&pArgc, &pArgv);
  fI18nInit();

  vIndicator = APP_INDICATOR(g_object_new(
    APP_INDICATOR_TYPE,
    "id", "phcc",
    "icon-name", "phcc",                 // PYMEHackers Control Center icon (hicolor theme)
    "category", "ApplicationStatus",
    NULL));

  app_indicator_set_status(vIndicator, APP_INDICATOR_STATUS_ACTIVE);
  app_indicator_set_title(vIndicator, fT("app.title"));
  fLoadCatalog(FALSE);

  gtk_main();
  fI18nFree();
  return 0;
}
