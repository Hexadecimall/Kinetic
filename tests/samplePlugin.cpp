#include "kinetic/pluginApi.h"

namespace {

const KineticPluginApi* pluginApi = nullptr;

void increaseSpacing(void*) {
    pluginApi->setNumber(pluginApi->context, "editor.text.letterSpacing", 2.0);
}

void onDocumentActivated(void*, const char*) {
    pluginApi->setNumber(pluginApi->context, "editor.text.letterSpacing", 3.0);
}

void appendDocumentLength(void*) {
    uint64_t length = pluginApi->copyDocumentUtf8(pluginApi->context, nullptr, 0);
    const char* suffix = length == 5 ? "!" : "?";
    pluginApi->replaceSelectionUtf8(pluginApi->context, suffix, 1);
}

int32_t startPlugin(const KineticPluginApi* api) {
    if (api == nullptr || api->abiVersion != kineticPluginAbiVersion ||
        api->structSize < sizeof(KineticPluginApi)) {
        return -1;
    }
    pluginApi = api;
    if (api->setNumber(api->context, "editor.text.letterSpacing", 1.25) != 0 ||
        api->registerCommand(api->context, "sample.increaseSpacing", "Increase Spacing",
                             increaseSpacing, nullptr) != 0 ||
        api->registerCommand(api->context, "sample.appendMarker", "Append Marker",
                             appendDocumentLength, nullptr) != 0 ||
        api->subscribeEvent(api->context, "document.activated", onDocumentActivated, nullptr) != 0) {
        return -1;
    }
    return 0;
}

const KineticPluginDescriptor descriptor = {
    kineticPluginAbiVersion,
    sizeof(KineticPluginDescriptor),
    "sample.structure",
    "Sample Structure Plugin",
    "1.0.0",
    startPlugin,
};

} // namespace

extern "C" const KineticPluginDescriptor* kineticPluginEntry(void) {
    return &descriptor;
}
