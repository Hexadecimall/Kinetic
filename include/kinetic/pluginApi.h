#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum { kineticPluginAbiVersion = 1 };

typedef void (*KineticPluginCommand)(void* userData);
typedef void (*KineticPluginEvent)(void* userData, const char* eventName);

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
} KineticPluginApi;

typedef struct KineticPluginDescriptor {
    uint32_t abiVersion;
    uint32_t structSize;
    const char* pluginId;
    const char* displayName;
    const char* version;
    int32_t (*start)(const KineticPluginApi* api);
} KineticPluginDescriptor;

// Export this exact symbol from a plugin dylib. Return static storage; Kinetic never frees it.
const KineticPluginDescriptor* kineticPluginEntry(void);

#ifdef __cplusplus
}
#endif
