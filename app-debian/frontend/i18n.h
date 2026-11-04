// i18n.h
// Translation support for the PYMEHackers Control Center indicator.
//
// Every visible text lives in <lang dir>/<language>.json (flat JSON object of string keys and
// string values). The supported languages are en-GB, en-US, es-AR and es-ES; en-US is the default
// and the fallback for any key missing from the selected language.

#ifndef PHCC_I18N_H
#define PHCC_I18N_H

#include <glib.h>

// Default folder of the language files installed by the phcc package. The PHCC_LANG_DIR
// environment variable overrides it (useful to run the indicator from the source tree).
#define cDefaultLangDir "/usr/share/pymehackers/core/lang"

// Resolves the language from the session locale and loads its file plus the en-US fallback.
void fI18nInit(void);

// Language selected by fI18nInit() (one of en-GB, en-US, es-AR, es-ES).
const char *fI18nLanguage(void);

// Text of a key in the selected language, falling back to en-US and finally to the key itself.
const char *fT(const char *pKey);

// Like fT(), replacing the placeholders {0}, {1}... with the given arguments. The argument list
// must end with NULL. The caller frees the result with g_free().
gchar *fTf(const char *pKey, ...) G_GNUC_NULL_TERMINATED;

// Releases the loaded translations.
void fI18nFree(void);

#endif
