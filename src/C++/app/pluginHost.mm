#import "pluginHost.h"

#include "kinetic/pluginApi.h"
#include "kineticBackend.h"

#include <cmath>
#include <dlfcn.h>
#include <stddef.h>
#include <string.h>

@interface KineticPluginSession : NSObject
@property(nonatomic, assign) KineticPluginHost* host;
@property(nonatomic, copy) NSString* pluginId;
@end

@implementation KineticPluginSession
@end

@interface KineticPluginHost () {
    NSMutableArray<NSString*>* _loadedPluginNames;
    NSMutableSet<NSString*>* _loadedPluginIds;
    NSMutableArray<NSDictionary<NSString*, id>*>* _registeredCommands;
    NSMutableArray<NSDictionary<NSString*, id>*>* _subscriptions;
    NSMutableArray<NSDictionary<NSString*, id>*>* _panelCallbacks;
    NSMutableArray<NSDictionary<NSString*, id>*>* _overlayCallbacks;
    NSMutableArray<NSDictionary<NSString*, id>*>* _formatterCallbacks;
    NSMutableArray<NSValue*>* _libraryHandles;
    NSMutableArray<KineticPluginSession*>* _sessions;
    NSMutableArray<NSValue*>* _apiTables;
    KineticExtensionRegistry* _registry;
    NSString* _loadingPluginId;
    NSString* _configurationError;
    KineticPluginApi _api;
    BOOL _emittingEvent;
}
- (void)contributionsDidChange;
@end

static int32_t setNumber(void* context, const char* property, double value);
static int32_t getNumber(void* context, const char* property, double* value);
static int32_t registerCommand(void* context, const char* commandId, const char* title,
                               KineticPluginCommand callback, void* userData);
static int32_t subscribeEvent(void* context, const char* eventName, KineticPluginEvent callback,
                              void* userData);
static uint64_t copyDocumentUtf8(void* context, char* buffer, uint64_t capacity);
static int32_t replaceSelectionUtf8(void* context, const char* text, uint64_t length);
static int32_t setString(void* context, const char* property, const char* text, uint64_t length);
static uint64_t copyString(void* context, const char* property, char* buffer, uint64_t capacity);
static int32_t getSelection(void* context, uint64_t* startUtf16, uint64_t* lengthUtf16);
static int32_t setSelection(void* context, uint64_t startUtf16, uint64_t lengthUtf16);
static int32_t replaceRangeUtf8(void* context, uint64_t startUtf16, uint64_t lengthUtf16,
                                const char* text, uint64_t byteLength);
static int32_t registerShortcut(void* context, const char* commandId, const char* key,
                                uint32_t modifiers);
static int32_t registerFileMenuItem(void* context, const char* commandId, const char* title);
static int32_t registerPanel(void* context, const char* panelId, const char* title,
                             KineticPluginPanelRows callback, void* userData);
static int32_t registerOverlay(void* context, const char* overlayId, KineticPluginOverlay callback,
                               void* userData);
static int32_t registerFormatter(void* context, const char* extension,
                                 KineticPluginFormatter callback, void* userData);
static NSString* registryField(KineticExtensionRegistry* registry, uint32_t kind, uint64_t index,
                               uint32_t field);

static NSString* trimmed(NSString* text) {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString* withoutComment(NSString* line) {
    BOOL quoted = NO;
    for (NSUInteger index = 0; index < line.length; ++index) {
        unichar character = [line characterAtIndex:index];
        if (character == '"') {
            quoted = !quoted;
        } else if (character == '#' && !quoted) {
            return [line substringToIndex:index];
        }
    }
    return line;
}

static NSSet<NSString*>* disabledFileList(NSString* value) {
    if (![value hasPrefix:@"["] || ![value hasSuffix:@"]"]) {
        return nil;
    }
    NSString* contents = trimmed([value substringWithRange:NSMakeRange(1, value.length - 2)]);
    if (contents.length == 0) {
        return [NSSet set];
    }
    NSMutableSet<NSString*>* names = [NSMutableSet set];
    NSArray<NSString*>* components = [contents componentsSeparatedByString:@","];
    for (NSUInteger index = 0; index < components.count; ++index) {
        NSString* component = components[index];
        NSString* item = trimmed(component);
        if (item.length == 0 && index + 1 == components.count) {
            continue;
        }
        if (item.length < 9 || ![item hasPrefix:@"\""] || ![item hasSuffix:@"\""]) {
            return nil;
        }
        NSString* name = [item substringWithRange:NSMakeRange(1, item.length - 2)];
        if (![name hasSuffix:@".dylib"] || [name containsString:@"/"] ||
            [name containsString:@"\\"] || [name containsString:@"\""] ||
            [name containsString:@".."] || [name containsString:@"#"] || name.length > 128) {
            return nil;
        }
        if ([names containsObject:name]) {
            return nil;
        }
        [names addObject:name];
    }
    return names;
}

static BOOL readPluginConfiguration(NSURL* configurationUrl, BOOL* enabled,
                                    NSSet<NSString*>** disabledFiles, NSString** errorMessage) {
    *enabled = YES;
    *disabledFiles = [NSSet set];
    if (![NSFileManager.defaultManager fileExistsAtPath:configurationUrl.path]) {
        return YES;
    }
    NSError* readError = nil;
    NSData* data = [NSData dataWithContentsOfURL:configurationUrl options:0 error:&readError];
    if (data == nil || data.length > 65536) {
        *errorMessage = @"Plugin config could not be read or exceeds 64 KiB.";
        return NO;
    }
    NSString* contents = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (contents == nil) {
        *errorMessage = @"Plugin config must be UTF-8.";
        return NO;
    }
    BOOL inPlugins = NO;
    BOOL sawPluginsSection = NO;
    BOOL sawEnabled = NO;
    BOOL sawDisabledFiles = NO;
    NSArray<NSString*>* lines =
        [contents componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSUInteger index = 0; index < lines.count; ++index) {
        NSString* line = trimmed(withoutComment(lines[index]));
        if (line.length == 0) {
            continue;
        }
        if ([line hasPrefix:@"["]) {
            if (![line hasSuffix:@"]"]) {
                *errorMessage =
                    [NSString stringWithFormat:@"Invalid plugin config section at line %lu.",
                                               (unsigned long)(index + 1)];
                return NO;
            }
            inPlugins = [line isEqualToString:@"[plugins]"];
            if (inPlugins && sawPluginsSection) {
                *errorMessage = @"The plugins table may appear only once.";
                return NO;
            }
            sawPluginsSection = sawPluginsSection || inPlugins;
            continue;
        }
        if (!inPlugins) {
            continue;
        }
        NSRange equals = [line rangeOfString:@"="];
        if (equals.location == NSNotFound) {
            *errorMessage = [NSString
                stringWithFormat:@"Invalid plugin config at line %lu.", (unsigned long)(index + 1)];
            return NO;
        }
        NSString* key = trimmed([line substringToIndex:equals.location]);
        NSString* value = trimmed([line substringFromIndex:equals.location + 1]);
        if ([key isEqualToString:@"enabled"] && !sawEnabled) {
            if (![value isEqualToString:@"true"] && ![value isEqualToString:@"false"]) {
                *errorMessage = @"plugins.enabled must be true or false.";
                return NO;
            }
            *enabled = [value isEqualToString:@"true"];
            sawEnabled = YES;
        } else if ([key isEqualToString:@"disabledFiles"] && !sawDisabledFiles) {
            NSSet<NSString*>* names = disabledFileList(value);
            if (names == nil) {
                *errorMessage = @"plugins.disabledFiles must list exact .dylib filenames.";
                return NO;
            }
            *disabledFiles = names;
            sawDisabledFiles = YES;
        } else {
            *errorMessage =
                [NSString stringWithFormat:@"Unknown or repeated plugin setting: %@.", key];
            return NO;
        }
    }
    return YES;
}

@implementation KineticPluginHost

+ (NSURL*)userPluginRootUrl {
    return [[NSURL fileURLWithPath:NSHomeDirectory()
                       isDirectory:YES] URLByAppendingPathComponent:@".kinetic" isDirectory:YES];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _loadedPluginNames = [NSMutableArray array];
        _loadedPluginIds = [NSMutableSet set];
        _registeredCommands = [NSMutableArray array];
        _subscriptions = [NSMutableArray array];
        _panelCallbacks = [NSMutableArray array];
        _overlayCallbacks = [NSMutableArray array];
        _formatterCallbacks = [NSMutableArray array];
        _libraryHandles = [NSMutableArray array];
        _sessions = [NSMutableArray array];
        _apiTables = [NSMutableArray array];
        _registry = kineticExtensionRegistryCreate();
        _api = {
            kineticPluginAbiVersion,
            sizeof(KineticPluginApi),
            nullptr,
            setNumber,
            getNumber,
            registerCommand,
            subscribeEvent,
            copyDocumentUtf8,
            replaceSelectionUtf8,
            setString,
            copyString,
            getSelection,
            setSelection,
            replaceRangeUtf8,
            registerShortcut,
            registerFileMenuItem,
            registerPanel,
            registerOverlay,
            registerFormatter,
        };
    }
    return self;
}

- (void)dealloc {
    kineticExtensionRegistryDestroy(_registry);
    for (NSValue* table in _apiTables) {
        delete (KineticPluginApi*)table.pointerValue;
    }
    for (NSValue* handle in _libraryHandles) {
        dlclose(handle.pointerValue);
    }
}

- (NSArray<NSString*>*)loadedPluginNames {
    return [_loadedPluginNames copy];
}

- (NSString*)configurationError {
    return _configurationError;
}

- (NSArray<NSDictionary<NSString*, NSString*>*>*)commands {
    NSMutableArray<NSDictionary<NSString*, NSString*>*>* result = [NSMutableArray array];
    for (uint64_t index = 0; index < kineticExtensionCount(_registry, kineticExtensionCommand);
         ++index) {
        NSString* identifier = registryField(_registry, kineticExtensionCommand, index, 1);
        NSString* title = registryField(_registry, kineticExtensionCommand, index, 2);
        if (identifier != nil && title != nil) {
            [result addObject:@{@"id" : identifier, @"title" : title}];
        }
    }
    return result;
}

static NSString* registryField(KineticExtensionRegistry* registry, uint32_t kind, uint64_t index,
                               uint32_t field) {
    uint64_t length = kineticExtensionCopyField(registry, kind, index, field, nullptr, 0);
    if (length == UINT64_MAX || length > 256) {
        return nil;
    }
    char buffer[257] = {};
    kineticExtensionCopyField(registry, kind, index, field, buffer, sizeof(buffer));
    return [NSString stringWithUTF8String:buffer];
}

- (NSArray<NSDictionary<NSString*, NSString*>*>*)fileMenuItems {
    NSMutableArray<NSDictionary<NSString*, NSString*>*>* items = [NSMutableArray array];
    for (uint64_t index = 0; index < kineticExtensionCount(_registry, kineticExtensionMenu);
         ++index) {
        NSString* identifier = registryField(_registry, kineticExtensionMenu, index, 1);
        NSString* title = registryField(_registry, kineticExtensionMenu, index, 2);
        if (identifier != nil && title != nil) {
            [items addObject:@{@"id" : identifier, @"title" : title}];
        }
    }
    return items;
}

static KineticPluginHost* hostForContext(void* context) {
    return ((__bridge KineticPluginSession*)context).host;
}

static NSString* ownerForContext(void* context) {
    return ((__bridge KineticPluginSession*)context).pluginId;
}

static NSString* stringForUtf8(const char* text) {
    return text == nullptr ? nil : [NSString stringWithUTF8String:text];
}

static int32_t setNumber(void* context, const char* property, double value) {
    if (![NSThread isMainThread]) {
        return -1;
    }
    KineticPluginHost* host = hostForContext(context);
    NSString* key = stringForUtf8(property);
    return key != nil && [host.delegate pluginHost:host setNumber:value property:key] ? 0 : -1;
}

static int32_t getNumber(void* context, const char* property, double* value) {
    if (![NSThread isMainThread]) {
        return -1;
    }
    KineticPluginHost* host = hostForContext(context);
    NSString* key = stringForUtf8(property);
    return key != nil && value != nullptr &&
                   [host.delegate pluginHost:host getNumber:value property:key]
               ? 0
               : -1;
}

static int32_t registerCommand(void* context, const char* commandId, const char* title,
                               KineticPluginCommand callback, void* userData) {
    if (![NSThread isMainThread]) {
        return -1;
    }
    KineticPluginHost* host = hostForContext(context);
    NSString* owner = ownerForContext(context);
    if (owner == nil) {
        return -1;
    }
    NSString* identifier = stringForUtf8(commandId);
    NSString* displayTitle = stringForUtf8(title);
    if (identifier.length == 0 || displayTitle.length == 0 || callback == nullptr ||
        identifier.length > 128 || displayTitle.length > 128) {
        return -1;
    }
    for (NSDictionary* command in host->_registeredCommands) {
        if ([command[@"id"] isEqualToString:identifier]) {
            return -1;
        }
    }
    if (kineticExtensionRegister(host->_registry, owner.UTF8String, kineticExtensionCommand,
                                 commandId, title, commandId) != 0) {
        return -1;
    }
    [host->_registeredCommands addObject:@{
        @"id" : identifier,
        @"title" : displayTitle,
        @"owner" : owner,
        @"callback" : [NSValue valueWithPointer:(void*)callback],
        @"userData" : [NSValue valueWithPointer:userData],
    }];
    [host contributionsDidChange];
    return 0;
}

static BOOL hasRegisteredCommand(KineticPluginHost* host, NSString* identifier, NSString* owner) {
    for (NSDictionary* command in host->_registeredCommands) {
        if ([command[@"id"] isEqualToString:identifier] &&
            (owner == nil || [command[@"owner"] isEqualToString:owner])) {
            return YES;
        }
    }
    return NO;
}

static int32_t registerShortcut(void* context, const char* commandId, const char* key,
                                uint32_t modifiers) {
    if (![NSThread isMainThread] || modifiers == 0 || modifiers > 31) {
        return -1;
    }
    KineticPluginHost* host = hostForContext(context);
    NSString* owner = ownerForContext(context);
    NSString* identifier = stringForUtf8(commandId);
    NSString* character = stringForUtf8(key).lowercaseString;
    if (owner == nil || !hasRegisteredCommand(host, identifier, owner) || character.length != 1 ||
        ![NSCharacterSet.alphanumericCharacterSet
            characterIsMember:[character characterAtIndex:0]]) {
        return -1;
    }
    NSString* target = [NSString stringWithFormat:@"%u:%@", modifiers, character];
    int32_t result =
        kineticExtensionRegister(host->_registry, owner.UTF8String, kineticExtensionShortcut,
                                 commandId, commandId, target.UTF8String);
    if (result == 0) {
        [host contributionsDidChange];
    }
    return result;
}

static int32_t registerFileMenuItem(void* context, const char* commandId, const char* title) {
    if (![NSThread isMainThread]) {
        return -1;
    }
    KineticPluginHost* host = hostForContext(context);
    NSString* owner = ownerForContext(context);
    NSString* identifier = stringForUtf8(commandId);
    NSString* displayTitle = stringForUtf8(title);
    if (owner == nil || !hasRegisteredCommand(host, identifier, owner) ||
        displayTitle.length == 0 || displayTitle.length > 128) {
        return -1;
    }
    int32_t result = kineticExtensionRegister(host->_registry, owner.UTF8String,
                                              kineticExtensionMenu, commandId, title, commandId);
    if (result == 0) {
        [host contributionsDidChange];
    }
    return result;
}

static int32_t registerPanel(void* context, const char* panelId, const char* title,
                             KineticPluginPanelRows callback, void* userData) {
    if (![NSThread isMainThread] || callback == nullptr) {
        return -1;
    }
    KineticPluginHost* host = hostForContext(context);
    NSString* owner = ownerForContext(context);
    NSString* identifier = stringForUtf8(panelId);
    NSString* displayTitle = stringForUtf8(title);
    if (owner == nil || identifier.length == 0 || displayTitle.length == 0 ||
        identifier.length > 128 || displayTitle.length > 128 ||
        kineticExtensionRegister(host->_registry, owner.UTF8String, kineticExtensionPanel, panelId,
                                 title, panelId) != 0) {
        return -1;
    }
    [host->_panelCallbacks addObject:@{
        @"id" : identifier,
        @"owner" : owner,
        @"callback" : [NSValue valueWithPointer:(void*)callback],
        @"userData" : [NSValue valueWithPointer:userData],
    }];
    [host contributionsDidChange];
    return 0;
}

static int32_t registerOverlay(void* context, const char* overlayId, KineticPluginOverlay callback,
                               void* userData) {
    if (![NSThread isMainThread] || callback == nullptr) {
        return -1;
    }
    KineticPluginHost* host = hostForContext(context);
    NSString* owner = ownerForContext(context);
    NSString* identifier = stringForUtf8(overlayId);
    if (owner == nil || identifier.length == 0 || identifier.length > 128 ||
        kineticExtensionRegister(host->_registry, owner.UTF8String, kineticExtensionOverlay,
                                 overlayId, overlayId, overlayId) != 0) {
        return -1;
    }
    [host->_overlayCallbacks addObject:@{
        @"id" : identifier,
        @"callback" : [NSValue valueWithPointer:(void*)callback],
        @"userData" : [NSValue valueWithPointer:userData],
    }];
    [host contributionsDidChange];
    return 0;
}

static int32_t registerFormatter(void* context, const char* extension,
                                 KineticPluginFormatter callback, void* userData) {
    if (![NSThread isMainThread] || callback == nullptr) {
        return -1;
    }
    KineticPluginHost* host = hostForContext(context);
    NSString* owner = ownerForContext(context);
    NSString* name = stringForUtf8(extension).lowercaseString;
    if (owner == nil || name.length == 0 || name.length > 24 ||
        [name rangeOfCharacterFromSet:NSCharacterSet.alphanumericCharacterSet.invertedSet]
                .location != NSNotFound ||
        kineticExtensionRegister(host->_registry, owner.UTF8String, kineticExtensionFormatter,
                                 name.UTF8String, name.UTF8String, name.UTF8String) != 0) {
        return -1;
    }
    [host->_formatterCallbacks addObject:@{
        @"extension" : name,
        @"callback" : [NSValue valueWithPointer:(void*)callback],
        @"userData" : [NSValue valueWithPointer:userData],
    }];
    [host contributionsDidChange];
    return 0;
}

static int32_t subscribeEvent(void* context, const char* eventName, KineticPluginEvent callback,
                              void* userData) {
    if (![NSThread isMainThread]) {
        return -1;
    }
    KineticPluginHost* host = hostForContext(context);
    NSString* name = stringForUtf8(eventName);
    if (name.length == 0 || name.length > 128 || callback == nullptr) {
        return -1;
    }
    [host->_subscriptions addObject:@{
        @"name" : name,
        @"callback" : [NSValue valueWithPointer:(void*)callback],
        @"userData" : [NSValue valueWithPointer:userData],
    }];
    return 0;
}

static uint64_t copyDocumentUtf8(void* context, char* buffer, uint64_t capacity) {
    if (![NSThread isMainThread]) {
        return 0;
    }
    KineticPluginHost* host = hostForContext(context);
    NSData* text =
        [[host.delegate pluginHostActiveDocument:host] dataUsingEncoding:NSUTF8StringEncoding];
    if (text == nil) {
        return 0;
    }
    if (buffer != nullptr && capacity > text.length) {
        memcpy(buffer, text.bytes, text.length);
        buffer[text.length] = '\0';
    }
    return text.length;
}

static int32_t replaceSelectionUtf8(void* context, const char* text, uint64_t length) {
    if (![NSThread isMainThread] || text == nullptr || length > 16 * 1024 * 1024) {
        return -1;
    }
    KineticPluginHost* host = hostForContext(context);
    NSString* replacement = [[NSString alloc] initWithBytes:text
                                                     length:(NSUInteger)length
                                                   encoding:NSUTF8StringEncoding];
    return replacement != nil && [host.delegate pluginHost:host replaceSelection:replacement] ? 0
                                                                                              : -1;
}

static int32_t setString(void* context, const char* property, const char* text, uint64_t length) {
    if (![NSThread isMainThread] || text == nullptr || length > 65536) {
        return -1;
    }
    KineticPluginHost* host = hostForContext(context);
    NSString* key = stringForUtf8(property);
    NSString* value = [[NSString alloc] initWithBytes:text
                                               length:(NSUInteger)length
                                             encoding:NSUTF8StringEncoding];
    return key != nil && value != nil &&
                   [host.delegate pluginHost:host setString:value property:key]
               ? 0
               : -1;
}

static uint64_t copyString(void* context, const char* property, char* buffer, uint64_t capacity) {
    if (![NSThread isMainThread]) {
        return UINT64_MAX;
    }
    KineticPluginHost* host = hostForContext(context);
    NSString* key = stringForUtf8(property);
    NSString* value = key == nil ? nil : [host.delegate pluginHost:host getString:key];
    NSData* bytes = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (bytes == nil) {
        return UINT64_MAX;
    }
    if (buffer != nullptr && capacity > bytes.length) {
        memcpy(buffer, bytes.bytes, bytes.length);
        buffer[bytes.length] = '\0';
    }
    return bytes.length;
}

static int32_t getSelection(void* context, uint64_t* startUtf16, uint64_t* lengthUtf16) {
    if (![NSThread isMainThread] || startUtf16 == nullptr || lengthUtf16 == nullptr) {
        return -1;
    }
    KineticPluginHost* host = hostForContext(context);
    NSRange selection = NSMakeRange(0, 0);
    if (![host.delegate pluginHost:host getSelection:&selection]) {
        return -1;
    }
    *startUtf16 = selection.location;
    *lengthUtf16 = selection.length;
    return 0;
}

static int32_t setSelection(void* context, uint64_t startUtf16, uint64_t lengthUtf16) {
    if (![NSThread isMainThread] || startUtf16 > NSUIntegerMax || lengthUtf16 > NSUIntegerMax ||
        startUtf16 + lengthUtf16 < startUtf16) {
        return -1;
    }
    KineticPluginHost* host = hostForContext(context);
    return [host.delegate pluginHost:host
                        setSelection:NSMakeRange((NSUInteger)startUtf16, (NSUInteger)lengthUtf16)]
               ? 0
               : -1;
}

static int32_t replaceRangeUtf8(void* context, uint64_t startUtf16, uint64_t lengthUtf16,
                                const char* text, uint64_t byteLength) {
    if (![NSThread isMainThread] || text == nullptr || byteLength > 16 * 1024 * 1024 ||
        startUtf16 > NSUIntegerMax || lengthUtf16 > NSUIntegerMax ||
        startUtf16 + lengthUtf16 < startUtf16) {
        return -1;
    }
    KineticPluginHost* host = hostForContext(context);
    NSString* replacement = [[NSString alloc] initWithBytes:text
                                                     length:(NSUInteger)byteLength
                                                   encoding:NSUTF8StringEncoding];
    return replacement != nil && [host.delegate pluginHost:host
                                              replaceRange:NSMakeRange((NSUInteger)startUtf16,
                                                                       (NSUInteger)lengthUtf16)
                                                withString:replacement]
               ? 0
               : -1;
}

- (void)loadPluginsAtUrl:(NSURL*)directoryUrl configurationUrl:(NSURL*)configurationUrl {
    BOOL enabled = YES;
    NSSet<NSString*>* disabledFiles = nil;
    NSString* errorMessage = nil;
    if (!readPluginConfiguration(configurationUrl, &enabled, &disabledFiles, &errorMessage)) {
        _configurationError = errorMessage;
        return;
    }
    _configurationError = nil;
    if (!enabled) {
        return;
    }
    NSArray<NSURL*>* urls = [NSFileManager.defaultManager
          contentsOfDirectoryAtURL:directoryUrl
        includingPropertiesForKeys:@[ NSURLIsRegularFileKey ]
                           options:NSDirectoryEnumerationSkipsHiddenFiles
                             error:nil];
    for (NSURL *url in
         [urls sortedArrayUsingComparator:^NSComparisonResult(NSURL* left, NSURL* right) {
           return [left.lastPathComponent compare:right.lastPathComponent];
         }]) {
        if (![url.pathExtension.lowercaseString isEqualToString:@"dylib"]) {
            continue;
        }
        if ([disabledFiles containsObject:url.lastPathComponent]) {
            continue;
        }
        NSNumber* regularFile = nil;
        [url getResourceValue:&regularFile forKey:NSURLIsRegularFileKey error:nil];
        if (!regularFile.boolValue) {
            continue;
        }
        void* handle = dlopen(url.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        if (handle == nullptr) {
            continue;
        }
        auto entry = (const KineticPluginDescriptor* (*)(void))dlsym(handle, "kineticPluginEntry");
        const KineticPluginDescriptor* descriptor = entry == nullptr ? nullptr : entry();
        if (descriptor == nullptr || descriptor->abiVersion != kineticPluginAbiVersion ||
            descriptor->structSize < sizeof(KineticPluginDescriptor) ||
            descriptor->start == nullptr || descriptor->pluginId == nullptr ||
            descriptor->displayName == nullptr || descriptor->version == nullptr) {
            dlclose(handle);
            continue;
        }
        NSString* pluginId = stringForUtf8(descriptor->pluginId);
        NSString* displayName = stringForUtf8(descriptor->displayName);
        if (pluginId.length == 0 || displayName.length == 0 || pluginId.length > 128 ||
            displayName.length > 128 || [_loadedPluginIds containsObject:pluginId]) {
            dlclose(handle);
            continue;
        }
        NSUInteger commandCount = _registeredCommands.count;
        NSUInteger subscriptionCount = _subscriptions.count;
        NSUInteger panelCount = _panelCallbacks.count;
        NSUInteger overlayCount = _overlayCallbacks.count;
        NSUInteger formatterCount = _formatterCallbacks.count;
        KineticPluginSession* session = [[KineticPluginSession alloc] init];
        session.host = self;
        session.pluginId = pluginId;
        auto apiTable = new KineticPluginApi(_api);
        apiTable->context = (__bridge void*)session;
        _loadingPluginId = pluginId;
        if (descriptor->start(apiTable) != 0) {
            kineticExtensionRemoveOwner(_registry, pluginId.UTF8String);
            [_registeredCommands
                removeObjectsInRange:NSMakeRange(commandCount,
                                                 _registeredCommands.count - commandCount)];
            [_subscriptions
                removeObjectsInRange:NSMakeRange(subscriptionCount,
                                                 _subscriptions.count - subscriptionCount)];
            [_panelCallbacks
                removeObjectsInRange:NSMakeRange(panelCount, _panelCallbacks.count - panelCount)];
            [_overlayCallbacks
                removeObjectsInRange:NSMakeRange(overlayCount,
                                                 _overlayCallbacks.count - overlayCount)];
            [_formatterCallbacks
                removeObjectsInRange:NSMakeRange(formatterCount,
                                                 _formatterCallbacks.count - formatterCount)];
            dlclose(handle);
            delete apiTable;
            _loadingPluginId = nil;
            continue;
        }
        _loadingPluginId = nil;
        [_sessions addObject:session];
        [_apiTables addObject:[NSValue valueWithPointer:apiTable]];
        [_libraryHandles addObject:[NSValue valueWithPointer:handle]];
        [_loadedPluginIds addObject:pluginId];
        [_loadedPluginNames addObject:displayName];
    }
}

- (BOOL)executeCommand:(NSString*)commandId {
    for (NSDictionary<NSString*, id>* command in _registeredCommands) {
        if ([command[@"id"] isEqualToString:commandId]) {
            auto callback = (KineticPluginCommand)[command[@"callback"] pointerValue];
            callback([command[@"userData"] pointerValue]);
            return YES;
        }
    }
    return NO;
}

- (BOOL)executeShortcutKey:(NSString*)key modifiers:(uint32_t)modifiers {
    NSString* target = [NSString stringWithFormat:@"%u:%@", modifiers, key.lowercaseString];
    for (uint64_t index = 0; index < kineticExtensionCount(_registry, kineticExtensionShortcut);
         ++index) {
        if ([registryField(_registry, kineticExtensionShortcut, index, 3) isEqualToString:target]) {
            return
                [self executeCommand:registryField(_registry, kineticExtensionShortcut, index, 1)];
        }
    }
    return NO;
}

- (NSArray<NSDictionary<NSString*, id>*>*)panels {
    NSMutableArray<NSDictionary<NSString*, id>*>* result = [NSMutableArray array];
    for (uint64_t index = 0; index < kineticExtensionCount(_registry, kineticExtensionPanel);
         ++index) {
        NSString* identifier = registryField(_registry, kineticExtensionPanel, index, 1);
        NSString* title = registryField(_registry, kineticExtensionPanel, index, 2);
        for (NSDictionary<NSString*, id>* panel in _panelCallbacks) {
            if (![panel[@"id"] isEqualToString:identifier]) {
                continue;
            }
            auto callback = (KineticPluginPanelRows)[panel[@"callback"] pointerValue];
            KineticPluginPanelRow rows[32] = {};
            uint32_t count = MIN(callback([panel[@"userData"] pointerValue], rows, 32), 32u);
            NSMutableArray<NSDictionary<NSString*, NSString*>*>* items = [NSMutableArray array];
            for (uint32_t row = 0; row < count; ++row) {
                size_t titleLength = strnlen(rows[row].title, sizeof(rows[row].title));
                NSString* rowTitle = [[NSString alloc] initWithBytes:rows[row].title
                                                              length:titleLength
                                                            encoding:NSUTF8StringEncoding];
                if (rowTitle.length == 0) {
                    continue;
                }
                if (rows[row].kind == kineticPluginPanelLabel) {
                    [items addObject:@{@"kind" : @"label", @"title" : rowTitle}];
                } else if (rows[row].kind == kineticPluginPanelButton) {
                    size_t idLength = strnlen(rows[row].commandId, sizeof(rows[row].commandId));
                    NSString* commandId = [[NSString alloc] initWithBytes:rows[row].commandId
                                                                   length:idLength
                                                                 encoding:NSUTF8StringEncoding];
                    if (hasRegisteredCommand(self, commandId, panel[@"owner"])) {
                        [items addObject:@{
                            @"kind" : @"button",
                            @"title" : rowTitle,
                            @"id" : commandId,
                        }];
                    }
                }
            }
            [result addObject:@{@"id" : identifier, @"title" : title, @"rows" : items}];
            break;
        }
    }
    return result;
}

- (BOOL)hasFormatterForFileName:(NSString*)fileName {
    NSString* extension = fileName.pathExtension.lowercaseString;
    for (NSDictionary<NSString*, id>* formatter in _formatterCallbacks) {
        if ([formatter[@"extension"] isEqualToString:extension]) {
            return YES;
        }
    }
    return NO;
}

- (NSString*)formatDocument:(NSString*)text fileName:(NSString*)fileName {
    NSString* extension = fileName.pathExtension.lowercaseString;
    NSData* input = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (input == nil || input.length > 16 * 1024 * 1024) {
        return nil;
    }
    for (NSDictionary<NSString*, id>* formatter in _formatterCallbacks) {
        if (![formatter[@"extension"] isEqualToString:extension]) {
            continue;
        }
        auto callback = (KineticPluginFormatter)[formatter[@"callback"] pointerValue];
        void* userData = [formatter[@"userData"] pointerValue];
        uint64_t length = callback(userData, (const char*)input.bytes, input.length, nullptr, 0);
        if (length > 16 * 1024 * 1024) {
            return nil;
        }
        NSMutableData* output = [NSMutableData dataWithLength:(NSUInteger)length + 1];
        uint64_t written = callback(userData, (const char*)input.bytes, input.length,
                                    (char*)output.mutableBytes, output.length);
        if (written != length) {
            return nil;
        }
        return [[NSString alloc] initWithBytes:output.bytes
                                        length:(NSUInteger)length
                                      encoding:NSUTF8StringEncoding];
    }
    return nil;
}

- (void)drawOverlaysInRect:(NSRect)rect {
    if (_overlayCallbacks.count == 0) {
        return;
    }
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:rect] addClip];
    for (NSDictionary<NSString*, id>* overlay in _overlayCallbacks) {
        auto callback = (KineticPluginOverlay)[overlay[@"callback"] pointerValue];
        KineticPluginDrawCommand commands[128] = {};
        uint32_t count = MIN(callback([overlay[@"userData"] pointerValue], NSWidth(rect),
                                      NSHeight(rect), commands, 128),
                             128u);
        for (uint32_t index = 0; index < count; ++index) {
            KineticPluginDrawCommand& command = commands[index];
            if (!std::isfinite(command.x) || !std::isfinite(command.y) ||
                !std::isfinite(command.width) || !std::isfinite(command.height) ||
                command.width < 0 || command.height < 0) {
                continue;
            }
            uint32_t rgba = command.rgba;
            NSColor* color = [NSColor colorWithSRGBRed:((rgba >> 24) & 255) / 255.0
                                                 green:((rgba >> 16) & 255) / 255.0
                                                  blue:((rgba >> 8) & 255) / 255.0
                                                 alpha:(rgba & 255) / 255.0];
            NSRect bounds = NSMakeRect(NSMinX(rect) + command.x, NSMinY(rect) + command.y,
                                       command.width, command.height);
            if (command.kind == kineticPluginDrawRect) {
                [color setFill];
                NSRectFill(bounds);
            } else if (command.kind == kineticPluginDrawText) {
                size_t length = strnlen(command.text, sizeof(command.text));
                NSString* text = [[NSString alloc] initWithBytes:command.text
                                                          length:length
                                                        encoding:NSUTF8StringEncoding];
                [text drawInRect:bounds
                    withAttributes:@{
                        NSFontAttributeName : [NSFont systemFontOfSize:12.0],
                        NSForegroundColorAttributeName : color,
                    }];
            }
        }
    }
    [NSGraphicsContext restoreGraphicsState];
}

- (void)emitEvent:(NSString*)eventName {
    if (_emittingEvent) {
        return;
    }
    _emittingEvent = YES;
    for (NSDictionary<NSString*, id>* subscription in [_subscriptions copy]) {
        if ([subscription[@"name"] isEqualToString:eventName]) {
            auto callback = (KineticPluginEvent)[subscription[@"callback"] pointerValue];
            callback([subscription[@"userData"] pointerValue], eventName.UTF8String);
        }
    }
    _emittingEvent = NO;
}

- (void)contributionsDidChange {
    if (_loadingPluginId == nil &&
        [self.delegate respondsToSelector:@selector(pluginHostContributionsDidChange:)]) {
        [self.delegate pluginHostContributionsDidChange:self];
    }
}

@end
