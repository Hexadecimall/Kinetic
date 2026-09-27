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
    int32_t (*subscribeEvent)(void* context, const char* eventName,
                              KineticPluginEvent callback, void* userData);
    uint64_t (*copyDocumentUtf8)(void* context, char* buffer, uint64_t capacity);
    int32_t (*replaceSelectionUtf8)(void* context, const char* text, uint64_t length);
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
