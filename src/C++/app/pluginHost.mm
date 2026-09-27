#import "pluginHost.h"

#include "kinetic/pluginApi.h"

#include <dlfcn.h>
#include <stddef.h>
#include <string.h>

@interface KineticPluginHost () {
    NSMutableArray<NSString*>* _loadedPluginNames;
    NSMutableSet<NSString*>* _loadedPluginIds;
    NSMutableArray<NSDictionary<NSString*, id>*>* _registeredCommands;
    NSMutableArray<NSDictionary<NSString*, id>*>* _subscriptions;
    NSMutableArray<NSValue*>* _libraryHandles;
    KineticPluginApi _api;
    BOOL _emittingEvent;
}
@end

static int32_t setNumber(void* context, const char* property, double value);
static int32_t getNumber(void* context, const char* property, double* value);
static int32_t registerCommand(void* context, const char* commandId, const char* title,
                               KineticPluginCommand callback, void* userData);
static int32_t subscribeEvent(void* context, const char* eventName, KineticPluginEvent callback,
                              void* userData);
static uint64_t copyDocumentUtf8(void* context, char* buffer, uint64_t capacity);
static int32_t replaceSelectionUtf8(void* context, const char* text, uint64_t length);

@implementation KineticPluginHost

- (instancetype)init {
    self = [super init];
    if (self) {
        _loadedPluginNames = [NSMutableArray array];
        _loadedPluginIds = [NSMutableSet set];
        _registeredCommands = [NSMutableArray array];
        _subscriptions = [NSMutableArray array];
        _libraryHandles = [NSMutableArray array];
        _api = {
            kineticPluginAbiVersion,
            sizeof(KineticPluginApi),
            (__bridge void*)self,
            setNumber,
            getNumber,
            registerCommand,
            subscribeEvent,
            copyDocumentUtf8,
            replaceSelectionUtf8,
        };
    }
    return self;
}

- (NSArray<NSString*>*)loadedPluginNames {
    return [_loadedPluginNames copy];
}

- (NSArray<NSDictionary<NSString*, NSString*>*>*)commands {
    NSMutableArray<NSDictionary<NSString*, NSString*>*>* result = [NSMutableArray array];
    for (NSDictionary<NSString*, id>* command in _registeredCommands) {
        [result addObject:@{@"id" : command[@"id"], @"title" : command[@"title"]}];
    }
    return result;
}

static KineticPluginHost* hostForContext(void* context) {
    return (__bridge KineticPluginHost*)context;
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
    [host->_registeredCommands addObject:@{
        @"id" : identifier,
        @"title" : displayTitle,
        @"callback" : [NSValue valueWithPointer:(void*)callback],
        @"userData" : [NSValue valueWithPointer:userData],
    }];
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

- (void)loadPluginsAtUrl:(NSURL*)directoryUrl {
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
        if (descriptor->start(&_api) != 0) {
            [_registeredCommands
                removeObjectsInRange:NSMakeRange(commandCount,
                                                 _registeredCommands.count - commandCount)];
            [_subscriptions
                removeObjectsInRange:NSMakeRange(subscriptionCount,
                                                 _subscriptions.count - subscriptionCount)];
            dlclose(handle);
            continue;
        }
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

@end
