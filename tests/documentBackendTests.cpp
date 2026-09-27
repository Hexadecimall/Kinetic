#include "kineticBackend.h"

#include <cassert>
#include <cstdint>
#include <cstring>

int main() {
    const char* original = "A\xF0\x9F\xA6\x80"
                           "B";
    KineticDocument* document =
        kineticDocumentCreate(reinterpret_cast<const uint8_t*>(original), std::strlen(original));
    assert(document != nullptr);
    assert(!kineticDocumentIsDirty(document));
    assert(kineticDocumentCheckpoint(document, 3, 3) == 0);
    const char* replacement = "Z";
    assert(kineticDocumentReplaceUtf8(document, 1, 2, reinterpret_cast<const uint8_t*>(replacement),
                                      1) == 0);
    assert(kineticDocumentIsDirty(document));
    char text[16] = {};
    assert(kineticDocumentCopyUtf8(document, reinterpret_cast<uint8_t*>(text), sizeof(text)) == 3);
    assert(std::strcmp(text, "AZB") == 0);
    uint64_t caret = 0;
    uint64_t anchor = 0;
    assert(kineticDocumentHistoryStep(document, false, 2, 2, &caret, &anchor) == 0);
    assert(caret == 3 && anchor == 3);
    assert(!kineticDocumentIsDirty(document));
    assert(kineticDocumentCanRedo(document));
    assert(kineticDocumentHistoryStep(document, true, caret, anchor, &caret, &anchor) == 0);
    assert(caret == 2 && anchor == 2);
    kineticDocumentMarkSaved(document);
    assert(!kineticDocumentIsDirty(document));
    kineticDocumentDestroy(document);
}
