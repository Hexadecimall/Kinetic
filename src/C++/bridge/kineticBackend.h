#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint32_t kineticBackendAbiVersion(void);
const char* kineticBackendVersion(void);

typedef struct KineticDocument KineticDocument;
typedef struct KineticExtensionRegistry KineticExtensionRegistry;

enum {
    kineticExtensionCommand = 1,
    kineticExtensionShortcut = 2,
    kineticExtensionMenu = 3,
    kineticExtensionPanel = 4,
    kineticExtensionOverlay = 5,
    kineticExtensionFormatter = 6,
    kineticExtensionSyntax = 7,
};

KineticExtensionRegistry* kineticExtensionRegistryCreate(void);
void kineticExtensionRegistryDestroy(KineticExtensionRegistry* registry);
int32_t kineticExtensionRegister(KineticExtensionRegistry* registry, const char* owner,
                                 uint32_t kind, const char* identifier, const char* title,
                                 const char* target);
void kineticExtensionRemoveOwner(KineticExtensionRegistry* registry, const char* owner);
uint64_t kineticExtensionCount(const KineticExtensionRegistry* registry, uint32_t kind);
uint64_t kineticExtensionCopyField(const KineticExtensionRegistry* registry, uint32_t kind,
                                   uint64_t index, uint32_t field, char* buffer, uint64_t capacity);

KineticDocument* kineticDocumentCreate(const uint8_t* bytes, uint64_t length);
void kineticDocumentDestroy(KineticDocument* document);
uint64_t kineticDocumentCopyUtf8(const KineticDocument* document, uint8_t* buffer,
                                 uint64_t capacity);
int32_t kineticDocumentCheckpoint(KineticDocument* document, uint64_t caret, uint64_t anchor);
int32_t kineticDocumentReplaceUtf8(KineticDocument* document, uint64_t startUtf16,
                                   uint64_t lengthUtf16, const uint8_t* bytes, uint64_t byteLength);
int32_t kineticDocumentHistoryStep(KineticDocument* document, bool redo, uint64_t currentCaret,
                                   uint64_t currentAnchor, uint64_t* nextCaret,
                                   uint64_t* nextAnchor);
bool kineticDocumentCanUndo(const KineticDocument* document);
bool kineticDocumentCanRedo(const KineticDocument* document);
bool kineticDocumentIsDirty(const KineticDocument* document);
void kineticDocumentMarkSaved(KineticDocument* document);

#ifdef __cplusplus
}
#endif
