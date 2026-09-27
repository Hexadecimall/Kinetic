#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum { kineticPluginAbiVersion = 1 };

enum {
    kineticPluginModifierCommand = 1,
    kineticPluginModifierShift = 2,
    kineticPluginModifierOption = 4,
    kineticPluginModifierControl = 8,
    kineticPluginModifierFunction = 16,
};

typedef void (*KineticPluginCommand)(void* userData);
typedef void (*KineticPluginEvent)(void* userData, const char* eventName);

enum { kineticPluginPanelLabel = 1, kineticPluginPanelButton = 2 };
typedef struct KineticPluginPanelRow {
    uint32_t kind;
    char title[96];
    char commandId[128];
} KineticPluginPanelRow;
typedef uint32_t (*KineticPluginPanelRows)(void* userData, KineticPluginPanelRow* rows,
                                           uint32_t capacity);

enum { kineticPluginDrawRect = 1, kineticPluginDrawText = 2 };
typedef struct KineticPluginDrawCommand {
    uint32_t kind;
    float x;
    float y;
    float width;
    float height;
    uint32_t rgba;
    char text[128];
} KineticPluginDrawCommand;
typedef uint32_t (*KineticPluginOverlay)(void* userData, float viewportWidth, float viewportHeight,
                                         KineticPluginDrawCommand* commands, uint32_t capacity);
typedef uint64_t (*KineticPluginFormatter)(void* userData, const char* input, uint64_t inputLength,
                                           char* output, uint64_t outputCapacity);

typedef struct KineticPluginSyntaxToken {
    uint32_t startUtf16;
    uint32_t lengthUtf16;
    uint32_t kind;
} KineticPluginSyntaxToken;
enum {
    kineticPluginSyntaxKeyword = 0,
    kineticPluginSyntaxString = 1,
    kineticPluginSyntaxComment = 2,
    kineticPluginSyntaxNumber = 3,
    kineticPluginSyntaxConstant = 4,
    kineticPluginSyntaxType = 5,
    kineticPluginSyntaxFunction = 6,
    kineticPluginSyntaxVariable = 7,
    kineticPluginSyntaxKey = 8,
    kineticPluginSyntaxDirective = 9,
};
typedef uint32_t (*KineticPluginSyntaxTokens)(void* userData, const char* line, uint64_t byteLength,
                                              uint32_t* state, KineticPluginSyntaxToken* tokens,
                                              uint32_t capacity);

typedef struct KineticPluginDiagnostic {
    uint32_t line;
    uint32_t columnUtf16;
    uint32_t lengthUtf16;
    uint32_t severity;
    char message[256];
} KineticPluginDiagnostic;
enum { kineticPluginError = 1, kineticPluginWarning = 2, kineticPluginInformation = 3 };

typedef struct KineticPluginApi {
    uint32_t abiVersion;
    uint32_t structSize;
    void* context;
    int32_t (*setNumber)(void* context, const char* property, double value);
    int32_t (*getNumber)(void* context, const char* property, double* value);
    int32_t (*registerCommand)(void* context, const char* commandId, const char* title,
                               KineticPluginCommand callback, void* userData);
    int32_t (*subscribeEvent)(void* context, const char* eventName, KineticPluginEvent callback,
                              void* userData);
    uint64_t (*copyDocumentUtf8)(void* context, char* buffer, uint64_t capacity);
    int32_t (*replaceSelectionUtf8)(void* context, const char* text, uint64_t length);
    int32_t (*setString)(void* context, const char* property, const char* text, uint64_t length);
    // UINT64_MAX means an unknown property; otherwise returns the required UTF-8 byte length.
    uint64_t (*copyString)(void* context, const char* property, char* buffer, uint64_t capacity);
    int32_t (*getSelection)(void* context, uint64_t* startUtf16, uint64_t* lengthUtf16);
    int32_t (*setSelection)(void* context, uint64_t startUtf16, uint64_t lengthUtf16);
    int32_t (*replaceRangeUtf8)(void* context, uint64_t startUtf16, uint64_t lengthUtf16,
                                const char* text, uint64_t byteLength);
    int32_t (*registerShortcut)(void* context, const char* commandId, const char* key,
                                uint32_t modifiers);
    int32_t (*registerFileMenuItem)(void* context, const char* commandId, const char* title);
    int32_t (*registerPanel)(void* context, const char* panelId, const char* title,
                             KineticPluginPanelRows callback, void* userData);
    int32_t (*registerOverlay)(void* context, const char* overlayId, KineticPluginOverlay callback,
                               void* userData);
    int32_t (*registerFormatter)(void* context, const char* extension,
                                 KineticPluginFormatter callback, void* userData);
    int32_t (*registerSyntaxProvider)(void* context, const char* extension,
                                      KineticPluginSyntaxTokens callback, void* userData);
    uint64_t (*copyActiveFilePath)(void* context, char* buffer, uint64_t capacity);
    uint64_t (*copyWorkspacePath)(void* context, char* buffer, uint64_t capacity);
    int32_t (*publishDiagnostics)(void* context, const char* filePath,
                                  const KineticPluginDiagnostic* diagnostics, uint32_t count);
    int32_t (*openLocation)(void* context, const char* filePath, uint32_t line,
                            uint32_t columnUtf16);
} KineticPluginApi;

typedef struct KineticPluginDescriptor {
    uint32_t abiVersion;
    uint32_t structSize;
    const char* pluginId;
    const char* displayName;
    const char* version;
    int32_t (*start)(const KineticPluginApi* api);
    // Optional trailing callback, checked against structSize before use.
    void (*stop)(void);
} KineticPluginDescriptor;

// Export this exact symbol from a plugin dylib. Return static storage; Kinetic never frees it.
const KineticPluginDescriptor* kineticPluginEntry(void);

#ifdef __cplusplus
}
#endif
