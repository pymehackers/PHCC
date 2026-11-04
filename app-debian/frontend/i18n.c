// i18n.c
// Translation support for the PYMEHackers Control Center indicator (see i18n.h).
//
// The language files are flat JSON objects ({"key": "text", ...}). GLib has no JSON parser and
// the files are tiny, so this file contains a small strict parser for exactly that shape: string
// keys, string values, and the standard JSON escapes (including \uXXXX and surrogate pairs).

#include "i18n.h"

#include <stdarg.h>
#include <string.h>

// Languages offered by the core, in alphabetical order. en-US is the default.
static const char *aSupportedLanguages[] = { "en-GB", "en-US", "es-AR", "es-ES" };
#define cDefaultLanguage "en-US"

static GHashTable *dSelected = NULL;   // texts of the selected language
static GHashTable *dFallback = NULL;   // texts of en-US
static const char *vLanguage = cDefaultLanguage;

// Skips JSON whitespace.
static void fSkipSpaces(const char **pCursor) {
  while (**pCursor == ' ' || **pCursor == '\t' || **pCursor == '\n' || **pCursor == '\r')
    (*pCursor)++;
}

// Reads 4 hexadecimal digits. Returns -1 if they are not valid.
static long fReadHex4(const char *pText) {
  long vValue = 0;
  for (int vIndex = 0; vIndex < 4; vIndex++) {
    char vChar = pText[vIndex];
    vValue <<= 4;
    if (vChar >= '0' && vChar <= '9')
      vValue |= vChar - '0';
    else if (vChar >= 'a' && vChar <= 'f')
      vValue |= vChar - 'a' + 10;
    else if (vChar >= 'A' && vChar <= 'F')
      vValue |= vChar - 'A' + 10;
    else
      return -1;
  }
  return vValue;
}

// Parses a JSON string starting at the opening quote. On success it advances the cursor past the
// closing quote and returns the decoded UTF-8 text; on error it returns NULL.
static gchar *fParseString(const char **pCursor) {
  const char *vCursor = *pCursor;
  if (*vCursor != '"')
    return NULL;
  vCursor++;

  GString *vText = g_string_new(NULL);
  while (*vCursor != '"') {
    if (*vCursor == '\0' || (unsigned char)*vCursor < 0x20) {
      g_string_free(vText, TRUE);
      return NULL;
    }
    if (*vCursor != '\\') {
      g_string_append_c(vText, *vCursor);
      vCursor++;
      continue;
    }

    // Escape sequence.
    vCursor++;
    switch (*vCursor) {
      case '"':  g_string_append_c(vText, '"');  break;
      case '\\': g_string_append_c(vText, '\\'); break;
      case '/':  g_string_append_c(vText, '/');  break;
      case 'b':  g_string_append_c(vText, '\b'); break;
      case 'f':  g_string_append_c(vText, '\f'); break;
      case 'n':  g_string_append_c(vText, '\n'); break;
      case 'r':  g_string_append_c(vText, '\r'); break;
      case 't':  g_string_append_c(vText, '\t'); break;
      case 'u': {
        long vCodePoint = fReadHex4(vCursor + 1);
        if (vCodePoint < 0) {
          g_string_free(vText, TRUE);
          return NULL;
        }
        vCursor += 4;
        // High surrogate: it must be followed by \uDC00-\uDFFF.
        if (vCodePoint >= 0xD800 && vCodePoint <= 0xDBFF) {
          long vLow = -1;
          if (vCursor[1] == '\\' && vCursor[2] == 'u')
            vLow = fReadHex4(vCursor + 3);
          if (vLow < 0xDC00 || vLow > 0xDFFF) {
            g_string_free(vText, TRUE);
            return NULL;
          }
          vCodePoint = 0x10000 + ((vCodePoint - 0xD800) << 10) + (vLow - 0xDC00);
          vCursor += 6;
        } else if (vCodePoint >= 0xDC00 && vCodePoint <= 0xDFFF) {
          g_string_free(vText, TRUE);
          return NULL;
        }
        g_string_append_unichar(vText, (gunichar)vCodePoint);
        break;
      }
      default:
        g_string_free(vText, TRUE);
        return NULL;
    }
    vCursor++;
  }

  *pCursor = vCursor + 1;
  if (!g_utf8_validate(vText->str, -1, NULL)) {
    g_string_free(vText, TRUE);
    return NULL;
  }
  return g_string_free(vText, FALSE);
}

// Parses a flat JSON object of strings into a new hash table. Returns NULL if the text is not
// exactly that shape.
static GHashTable *fParseObject(const char *pText) {
  GHashTable *dTexts = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);
  const char *vCursor = pText;

  fSkipSpaces(&vCursor);
  if (*vCursor != '{')
    goto Invalid;
  vCursor++;
  fSkipSpaces(&vCursor);

  if (*vCursor == '}') {
    vCursor++;
  } else {
    while (TRUE) {
      fSkipSpaces(&vCursor);
      gchar *vKey = fParseString(&vCursor);
      if (vKey == NULL)
        goto Invalid;
      fSkipSpaces(&vCursor);
      if (*vCursor != ':') {
        g_free(vKey);
        goto Invalid;
      }
      vCursor++;
      fSkipSpaces(&vCursor);
      gchar *vValue = fParseString(&vCursor);
      if (vValue == NULL) {
        g_free(vKey);
        goto Invalid;
      }
      g_hash_table_replace(dTexts, vKey, vValue);
      fSkipSpaces(&vCursor);
      if (*vCursor == ',') {
        vCursor++;
        continue;
      }
      if (*vCursor == '}') {
        vCursor++;
        break;
      }
      goto Invalid;
    }
  }

  fSkipSpaces(&vCursor);
  if (*vCursor != '\0')
    goto Invalid;
  return dTexts;

Invalid:
  g_hash_table_destroy(dTexts);
  return NULL;
}

// Loads <pDir>/<pLanguage>.json. Returns NULL (and logs a warning) if it cannot be read or parsed.
static GHashTable *fLoadLanguage(const char *pDir, const char *pLanguage) {
  gchar *vPath = g_strdup_printf("%s/%s.json", pDir, pLanguage);
  gchar *vContent = NULL;
  GError *vError = NULL;
  GHashTable *dTexts = NULL;

  if (!g_file_get_contents(vPath, &vContent, NULL, &vError)) {
    g_warning("PYMEHackers: could not read the language file '%s': %s",
              vPath, vError != NULL ? vError->message : "unknown error");
    if (vError != NULL)
      g_error_free(vError);
  } else {
    dTexts = fParseObject(vContent);
    if (dTexts == NULL)
      g_warning("PYMEHackers: the language file '%s' is not a valid flat JSON object", vPath);
  }

  g_free(vContent);
  g_free(vPath);
  return dTexts;
}

// Maps one locale name (es_AR.UTF-8, en_GB, es, C...) to a supported language, or NULL.
// An exact match (language and region) wins; otherwise the language alone picks its default
// variant: "en" -> en-US, "es" -> es-ES.
static const char *fMatchLanguage(const char *pLocale) {
  gchar *vTag = g_strdup(pLocale);
  const char *vResult = NULL;

  // Drop the codeset (.UTF-8) and the modifier (@euro) and use '-' as separator.
  char *vCut = strpbrk(vTag, ".@");
  if (vCut != NULL)
    *vCut = '\0';
  g_strdelimit(vTag, "_", '-');

  for (size_t vIndex = 0; vIndex < G_N_ELEMENTS(aSupportedLanguages); vIndex++) {
    if (g_ascii_strcasecmp(vTag, aSupportedLanguages[vIndex]) == 0) {
      vResult = aSupportedLanguages[vIndex];
      break;
    }
  }
  if (vResult == NULL) {
    if (g_ascii_strncasecmp(vTag, "en", 2) == 0 && (vTag[2] == '\0' || vTag[2] == '-'))
      vResult = "en-US";
    else if (g_ascii_strncasecmp(vTag, "es", 2) == 0 && (vTag[2] == '\0' || vTag[2] == '-'))
      vResult = "es-ES";
  }

  g_free(vTag);
  return vResult;
}

void fI18nInit(void) {
  const char *vLangDir = g_getenv("PHCC_LANG_DIR");
  if (vLangDir == NULL || vLangDir[0] == '\0')
    vLangDir = cDefaultLangDir;

  // g_get_language_names() follows LANGUAGE, LC_ALL, LC_MESSAGES and LANG, most preferred first.
  vLanguage = cDefaultLanguage;
  const gchar * const *aLocales = g_get_language_names();
  for (size_t vIndex = 0; aLocales[vIndex] != NULL; vIndex++) {
    const char *vMatch = fMatchLanguage(aLocales[vIndex]);
    if (vMatch != NULL) {
      vLanguage = vMatch;
      break;
    }
  }

  fI18nFree();
  dFallback = fLoadLanguage(vLangDir, cDefaultLanguage);
  if (strcmp(vLanguage, cDefaultLanguage) != 0)
    dSelected = fLoadLanguage(vLangDir, vLanguage);
}

const char *fI18nLanguage(void) {
  return vLanguage;
}

const char *fT(const char *pKey) {
  const char *vText = NULL;
  if (dSelected != NULL)
    vText = g_hash_table_lookup(dSelected, pKey);
  if (vText == NULL && dFallback != NULL)
    vText = g_hash_table_lookup(dFallback, pKey);
  return vText != NULL ? vText : pKey;
}

gchar *fTf(const char *pKey, ...) {
  GString *vResult = g_string_new(fT(pKey));
  va_list vArguments;
  va_start(vArguments, pKey);
  const char *vArgument;
  for (int vIndex = 0; (vArgument = va_arg(vArguments, const char *)) != NULL; vIndex++) {
    gchar *vPlaceholder = g_strdup_printf("{%d}", vIndex);
    g_string_replace(vResult, vPlaceholder, vArgument, 0);
    g_free(vPlaceholder);
  }
  va_end(vArguments);
  return g_string_free(vResult, FALSE);
}

void fI18nFree(void) {
  if (dSelected != NULL)
    g_hash_table_destroy(dSelected);
  if (dFallback != NULL)
    g_hash_table_destroy(dFallback);
  dSelected = NULL;
  dFallback = NULL;
}
