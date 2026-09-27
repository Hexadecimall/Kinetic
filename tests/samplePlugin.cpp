#include "kinetic/pluginApi.h"

#include <cstring>

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

void replaceFirstCharacter(void*) {
    pluginApi->replaceRangeUtf8(pluginApi->context, 0, 1, "H", 1);
}

void installLateAction(void*) {
    pluginApi->registerFileMenuItem(pluginApi->context, "sample.appendMarker", "Append Marker");
    pluginApi->registerShortcut(pluginApi->context, "sample.appendMarker", "l",
                                kineticPluginModifierCommand | kineticPluginModifierShift);
}

uint32_t panelRows(void*, KineticPluginPanelRow* rows, uint32_t capacity) {
    if (capacity < 2) {
        return 0;
    }
    rows[0].kind = kineticPluginPanelLabel;
    std::strcpy(rows[0].title, "Sample tools are ready.");
    rows[1].kind = kineticPluginPanelButton;
    std::strcpy(rows[1].title, "Replace First");
    std::strcpy(rows[1].commandId, "sample.replaceFirst");
    return 2;
}

uint32_t overlay(void*, float, float, KineticPluginDrawCommand* commands, uint32_t capacity) {
    if (capacity == 0) {
        return 0;
    }
    commands[0].kind = kineticPluginDrawRect;
    commands[0].x = 8.0f;
    commands[0].y = 8.0f;
    commands[0].width = 4.0f;
    commands[0].height = 4.0f;
    commands[0].rgba = 0x4d8dffff;
    return 1;
}

uint64_t formatSample(void*, const char* input, uint64_t length, char* output, uint64_t capacity) {
    if (output != nullptr && capacity > length) {
        for (uint64_t index = 0; index < length; ++index) {
            char character = input[index];
            output[index] = character >= 'a' && character <= 'z' ? character - 32 : character;
        }
        output[length] = '\0';
    }
    return length;
}

int32_t startPlugin(const KineticPluginApi* api) {
    if (api == nullptr || api->abiVersion != kineticPluginAbiVersion ||
        api->structSize < sizeof(KineticPluginApi)) {
        return -1;
    }
    pluginApi = api;
    char background[8] = {};
    uint64_t start = 0;
    uint64_t length = 0;
    if (api->setNumber(api->context, "editor.text.letterSpacing", 1.25) != 0 ||
        api->setString(api->context, "editor.canvas.background", "#2A3647", 7) != 0 ||
        api->copyString(api->context, "editor.canvas.background", background, sizeof(background)) !=
            7 ||
        api->getSelection(api->context, &start, &length) != 0 || start != 5 || length != 0 ||
        api->setSelection(api->context, 5, 0) != 0 ||
        api->registerCommand(api->context, "sample.increaseSpacing", "Increase Spacing",
                             increaseSpacing, nullptr) != 0 ||
        api->registerCommand(api->context, "sample.appendMarker", "Append Marker",
                             appendDocumentLength, nullptr) != 0 ||
        api->registerCommand(api->context, "sample.replaceFirst", "Replace First",
                             replaceFirstCharacter, nullptr) != 0 ||
        api->registerCommand(api->context, "sample.installLate", "Install Late Action",
                             installLateAction, nullptr) != 0 ||
        api->registerShortcut(api->context, "sample.increaseSpacing", "p",
                              kineticPluginModifierCommand | kineticPluginModifierShift) != 0 ||
        api->registerFileMenuItem(api->context, "sample.replaceFirst", "Replace First") != 0 ||
        api->registerPanel(api->context, "sample.panel", "Sample Tools", panelRows, nullptr) != 0 ||
        api->registerOverlay(api->context, "sample.overlay", overlay, nullptr) != 0 ||
        api->registerFormatter(api->context, "kineticdemo", formatSample, nullptr) != 0 ||
        api->subscribeEvent(api->context, "document.activated", onDocumentActivated, nullptr) !=
            0) {
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
