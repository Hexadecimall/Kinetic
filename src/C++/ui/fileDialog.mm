#import "fileDialog.h"
#import "contextMenu.h"

namespace {
constexpr CGFloat kRowHeight = 30.0;

NSColor* dialogColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha = 1.0) {
    return [NSColor colorWithSRGBRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:alpha];
}

BOOL dialogIsDirectory(NSURL* url) {
    BOOL directory = NO;
    [NSFileManager.defaultManager fileExistsAtPath:url.path isDirectory:&directory];
    return directory;
}
} // namespace

@interface KineticFileEntry : NSObject
@property(nonatomic, strong) NSURL* url;
@property(nonatomic, copy) NSString* name;
@property(nonatomic) BOOL directory;
@end

@implementation KineticFileEntry
@end

@interface KineticFileDialog () {
    KineticFileDialogMode _mode;
    id<KineticFileDialogDelegate> _dialogDelegate;
    NSURL* _directoryUrl;
    NSURL* _creationRootUrl;
    NSArray<KineticFileEntry*>* _entries;
    NSMutableString* _fileName;
    NSString* _errorMessage;
    NSRect _panelRect;
    NSRect _upRect;
    NSRect _listRect;
    NSRect _nameFieldRect;
    NSRect _cancelRect;
    NSRect _confirmRect;
    NSTrackingArea* _trackingArea;
    NSInteger _selectedIndex;
    NSInteger _hoveredButton;
    CGFloat _scrollOffset;
    BOOL _editingFileName;
}
@end

@implementation KineticFileDialog

- (instancetype)initWithFrame:(NSRect)frameRect
                         mode:(KineticFileDialogMode)mode
                  initialPath:(NSString*)initialPath
                     delegate:(id<KineticFileDialogDelegate>)delegate {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.opaque = NO;
        _mode = mode;
        _dialogDelegate = delegate;
        _selectedIndex = -1;
        _hoveredButton = -1;
        _editingFileName = mode == KineticFileDialogModeSave ||
                           mode == KineticFileDialogModeCreateFolder ||
                           mode == KineticFileDialogModeCreateFile;
        NSString* expandedPath = [initialPath stringByExpandingTildeInPath];
        if (mode == KineticFileDialogModeSave) {
            _directoryUrl = [NSURL fileURLWithPath:expandedPath.stringByDeletingLastPathComponent
                                       isDirectory:YES];
            _fileName = [[NSMutableString alloc] initWithString:expandedPath.lastPathComponent];
        } else {
            _directoryUrl = [NSURL fileURLWithPath:expandedPath isDirectory:YES];
            _fileName = [[NSMutableString alloc] init];
            if (mode == KineticFileDialogModeCreateFolder ||
                mode == KineticFileDialogModeCreateFile) {
                _creationRootUrl = _directoryUrl;
            }
        }
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self reloadEntries];
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)requiresName {
    return _mode == KineticFileDialogModeSave || _mode == KineticFileDialogModeCreateFolder ||
           _mode == KineticFileDialogModeCreateFile;
}

- (void)layoutRects {
    CGFloat width = MIN(690.0, NSWidth(self.bounds) - 48.0);
    CGFloat height = MIN(500.0, NSHeight(self.bounds) - 48.0);
    _panelRect = NSMakeRect(floor((NSWidth(self.bounds) - width) * 0.5),
                            floor((NSHeight(self.bounds) - height) * 0.46), width, height);
    _upRect = NSMakeRect(NSMinX(_panelRect) + 24.0, NSMinY(_panelRect) + 58.0, 30.0, 28.0);
    CGFloat listHeight = [self requiresName] ? height - 194.0 : height - 158.0;
    _listRect = NSMakeRect(NSMinX(_panelRect) + 24.0, NSMinY(_panelRect) + 98.0,
                           NSWidth(_panelRect) - 48.0, listHeight);
    _nameFieldRect = NSMakeRect(NSMinX(_panelRect) + 24.0, NSMaxY(_listRect) + 12.0,
                                NSWidth(_panelRect) - 48.0, 32.0);
    _cancelRect = NSMakeRect(NSMaxX(_panelRect) - 190.0, NSMaxY(_panelRect) - 44.0, 72.0, 28.0);
    _confirmRect = NSMakeRect(NSMaxX(_panelRect) - 108.0, NSMaxY(_panelRect) - 44.0, 84.0, 28.0);
}

- (void)reloadEntries {
    NSError* error = nil;
    NSArray<NSURL*>* urls =
        [NSFileManager.defaultManager contentsOfDirectoryAtURL:_directoryUrl
                                    includingPropertiesForKeys:@[ NSURLIsDirectoryKey ]
                                                       options:0
                                                         error:&error];
    if (urls == nil) {
        _entries = @[];
        _errorMessage = @"Kinetic cannot read this folder.";
        return;
    }

    NSMutableArray<KineticFileEntry*>* entries = [[NSMutableArray alloc] init];
    for (NSURL* url in urls) {
        KineticFileEntry* entry = [[KineticFileEntry alloc] init];
        entry.url = url;
        entry.name = url.lastPathComponent;
        entry.directory = dialogIsDirectory(url);
        [entries addObject:entry];
    }
    [entries
        sortUsingComparator:^NSComparisonResult(KineticFileEntry* left, KineticFileEntry* right) {
          if (left.directory != right.directory) {
              return left.directory ? NSOrderedAscending : NSOrderedDescending;
          }
          return [left.name localizedCaseInsensitiveCompare:right.name];
        }];
    _entries = entries;
    _selectedIndex = -1;
    _scrollOffset = 0.0;
    _errorMessage = nil;
    self.needsDisplay = YES;
}

- (CGFloat)maximumScrollOffset {
    return MAX(0.0, _entries.count * kRowHeight - NSHeight(_listRect));
}

- (NSInteger)entryIndexAtPoint:(NSPoint)point {
    if (!NSPointInRect(point, _listRect)) {
        return -1;
    }
    NSInteger index = floor((point.y - NSMinY(_listRect) + _scrollOffset) / kRowHeight);
    return index >= 0 && index < (NSInteger)_entries.count ? index : -1;
}

- (void)drawFolderIconInRect:(NSRect)rect color:(NSColor*)color {
    NSBezierPath* icon = [NSBezierPath bezierPath];
    [icon moveToPoint:NSMakePoint(NSMinX(rect), NSMinY(rect) + 4.0)];
    [icon lineToPoint:NSMakePoint(NSMinX(rect) + 6.0, NSMinY(rect) + 4.0)];
    [icon lineToPoint:NSMakePoint(NSMinX(rect) + 8.0, NSMinY(rect) + 1.0)];
    [icon lineToPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect) + 1.0)];
    [icon lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
    [icon lineToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
    [icon closePath];
    icon.lineWidth = 1.2;
    [color setStroke];
    [icon stroke];
}

- (void)drawFileIconInRect:(NSRect)rect color:(NSColor*)color {
    NSBezierPath* icon = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:1.5 yRadius:1.5];
    icon.lineWidth = 1.2;
    [color setStroke];
    [icon stroke];
}

- (void)drawButtonInRect:(NSRect)rect
                   title:(NSString*)title
                 primary:(BOOL)primary
                 hovered:(BOOL)hovered {
    NSColor* fill = primary ? dialogColor(77, 141, 255) : dialogColor(55, 67, 83);
    if (hovered) {
        fill = primary ? dialogColor(102, 158, 255) : dialogColor(67, 81, 99);
    }
    [fill setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:4.0 yRadius:4.0] fill];
    NSDictionary* attributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName : dialogColor(244, 247, 252),
    };
    NSSize size = [title sizeWithAttributes:attributes];
    [title drawAtPoint:NSMakePoint(NSMidX(rect) - size.width * 0.5,
                                   NSMidY(rect) - size.height * 0.5)
        withAttributes:attributes];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [self layoutRects];
    _scrollOffset = MIN(_scrollOffset, [self maximumScrollOffset]);

    [dialogColor(5, 8, 13, 0.52) setFill];
    NSRectFill(self.bounds);
    [dialogColor(39, 48, 61) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:_panelRect xRadius:8.0 yRadius:8.0] fill];

    NSDictionary* titleAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:16.0 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName : dialogColor(235, 240, 247),
    };
    NSString* title = @"Open File";
    if (_mode == KineticFileDialogModeOpenFolder) {
        title = @"Open Folder";
    } else if (_mode == KineticFileDialogModeSave) {
        title = @"Save File";
    } else if (_mode == KineticFileDialogModeCreateFolder) {
        title = @"New Folder";
    } else if (_mode == KineticFileDialogModeCreateFile) {
        title = @"New File";
    }
    [title drawAtPoint:NSMakePoint(NSMinX(_panelRect) + 24.0, NSMinY(_panelRect) + 22.0)
        withAttributes:titleAttributes];

    [dialogColor(55, 67, 83) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:_upRect xRadius:4.0 yRadius:4.0] fill];
    NSBezierPath* upIcon = [NSBezierPath bezierPath];
    upIcon.lineWidth = 1.3;
    upIcon.lineCapStyle = NSLineCapStyleRound;
    [upIcon moveToPoint:NSMakePoint(NSMidX(_upRect) - 5.0, NSMidY(_upRect) + 2.0)];
    [upIcon lineToPoint:NSMakePoint(NSMidX(_upRect), NSMidY(_upRect) - 3.0)];
    [upIcon lineToPoint:NSMakePoint(NSMidX(_upRect) + 5.0, NSMidY(_upRect) + 2.0)];
    [dialogColor(218, 226, 237) setStroke];
    [upIcon stroke];

    NSMutableParagraphStyle* pathStyle = [[NSMutableParagraphStyle alloc] init];
    pathStyle.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSDictionary* pathAttributes = @{
        NSFontAttributeName : [NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : dialogColor(170, 184, 201),
        NSParagraphStyleAttributeName : pathStyle,
    };
    [_directoryUrl.path drawInRect:NSMakeRect(NSMaxX(_upRect) + 12.0, NSMinY(_upRect) + 6.0,
                                              NSWidth(_panelRect) - 102.0, 18.0)
                    withAttributes:pathAttributes];

    [dialogColor(30, 38, 50) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:_listRect xRadius:4.0 yRadius:4.0] fill];
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:_listRect] addClip];
    NSDictionary* entryAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : dialogColor(218, 226, 237),
    };
    for (NSUInteger index = 0; index < _entries.count; ++index) {
        CGFloat y = NSMinY(_listRect) + index * kRowHeight - _scrollOffset;
        NSRect rowRect = NSMakeRect(NSMinX(_listRect), y, NSWidth(_listRect), kRowHeight);
        if (!NSIntersectsRect(rowRect, _listRect)) {
            continue;
        }
        if ((NSInteger)index == _selectedIndex) {
            [dialogColor(39, 59, 91) setFill];
            NSRectFill(NSInsetRect(rowRect, 3.0, 2.0));
        }
        KineticFileEntry* entry = _entries[index];
        NSRect iconRect = NSMakeRect(NSMinX(rowRect) + 11.0, NSMidY(rowRect) - 6.0, 14.0, 12.0);
        if (entry.directory) {
            [self drawFolderIconInRect:iconRect color:dialogColor(111, 166, 255)];
        } else {
            [self drawFileIconInRect:NSInsetRect(iconRect, 2.0, 0.0)
                               color:dialogColor(157, 171, 190)];
        }
        [entry.name drawAtPoint:NSMakePoint(NSMinX(rowRect) + 34.0, NSMinY(rowRect) + 7.0)
                 withAttributes:entryAttributes];
    }
    [NSGraphicsContext restoreGraphicsState];

    CGFloat maximumScroll = [self maximumScrollOffset];
    if (maximumScroll > 0.0) {
        NSRect track = NSMakeRect(NSMaxX(_listRect) - 6.0, NSMinY(_listRect) + 4.0, 3.0,
                                  NSHeight(_listRect) - 8.0);
        CGFloat contentHeight = _entries.count * kRowHeight;
        CGFloat thumbHeight = MAX(28.0, NSHeight(track) * NSHeight(track) / contentHeight);
        CGFloat thumbY =
            NSMinY(track) + (NSHeight(track) - thumbHeight) * (_scrollOffset / maximumScroll);
        [dialogColor(139, 155, 177, 0.42) setFill];
        [[NSBezierPath
            bezierPathWithRoundedRect:NSMakeRect(NSMinX(track), thumbY, NSWidth(track), thumbHeight)
                              xRadius:1.5
                              yRadius:1.5] fill];
    }

    if ([self requiresName]) {
        [dialogColor(30, 38, 50, 0.96) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:_nameFieldRect xRadius:4.0 yRadius:4.0] fill];
        [dialogColor(77, 141, 255, 0.74) setStroke];
        [[NSBezierPath bezierPathWithRoundedRect:_nameFieldRect xRadius:4.0 yRadius:4.0] stroke];
        NSDictionary* nameAttributes = @{
            NSFontAttributeName : [NSFont monospacedSystemFontOfSize:12.0
                                                              weight:NSFontWeightRegular],
            NSForegroundColorAttributeName : dialogColor(226, 233, 242),
        };
        NSPoint namePoint = NSMakePoint(NSMinX(_nameFieldRect) + 9.0, NSMinY(_nameFieldRect) + 8.0);
        [_fileName drawAtPoint:namePoint withAttributes:nameAttributes];
        if (_fileName.length == 0) {
            [(_mode == KineticFileDialogModeCreateFolder ? @"Folder name" : @"File name")
                   drawAtPoint:namePoint
                withAttributes:@{
                    NSFontAttributeName : nameAttributes[NSFontAttributeName],
                    NSForegroundColorAttributeName : dialogColor(132, 146, 166),
                }];
        }
        if (_editingFileName) {
            CGFloat caretX = namePoint.x + [_fileName sizeWithAttributes:nameAttributes].width +
                             (_fileName.length == 0 ? -3.0 : 1.0);
            [dialogColor(111, 166, 255) setFill];
            NSRectFill(NSMakeRect(caretX, namePoint.y, 1.5, 16.0));
        }
    }

    if (_errorMessage.length > 0) {
        NSDictionary* errorAttributes = @{
            NSFontAttributeName : [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName : dialogColor(255, 122, 97),
        };
        [_errorMessage drawAtPoint:NSMakePoint(NSMinX(_panelRect) + 24.0, NSMaxY(_panelRect) - 37.0)
                    withAttributes:errorAttributes];
    }
    [self drawButtonInRect:_cancelRect title:@"Cancel" primary:NO hovered:_hoveredButton == 0];
    [self drawButtonInRect:_confirmRect
                     title:_mode == KineticFileDialogModeSave ? @"Save"
                           : _mode == KineticFileDialogModeCreateFolder ||
                                   _mode == KineticFileDialogModeCreateFile
                               ? @"Create"
                               : @"Open"
                   primary:YES
                   hovered:_hoveredButton == 1];
}

- (void)showError:(NSString*)message {
    _errorMessage = [message copy];
    self.needsDisplay = YES;
}

- (void)openSelectedEntry {
    if (_selectedIndex < 0 || _selectedIndex >= (NSInteger)_entries.count) {
        return;
    }
    KineticFileEntry* entry = _entries[(NSUInteger)_selectedIndex];
    if (entry.directory) {
        _directoryUrl = entry.url;
        [self reloadEntries];
    } else if (_mode == KineticFileDialogModeOpen) {
        [_dialogDelegate fileDialog:self didChoosePath:entry.url.path mode:_mode];
    } else if (_mode == KineticFileDialogModeSave) {
        [_fileName setString:entry.name];
        _editingFileName = YES;
        self.needsDisplay = YES;
    }
}

- (void)confirm {
    if (_mode == KineticFileDialogModeOpen) {
        [self openSelectedEntry];
        return;
    }
    if (_mode == KineticFileDialogModeOpenFolder) {
        NSURL* selectedUrl = _directoryUrl;
        if (_selectedIndex >= 0 && _selectedIndex < (NSInteger)_entries.count &&
            _entries[(NSUInteger)_selectedIndex].directory) {
            selectedUrl = _entries[(NSUInteger)_selectedIndex].url;
        }
        [_dialogDelegate fileDialog:self didChoosePath:selectedUrl.path mode:_mode];
        return;
    }
    if (_mode == KineticFileDialogModeCreateFolder || _mode == KineticFileDialogModeCreateFile) {
        NSString* name = [_fileName
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length == 0) {
            [self showError:_mode == KineticFileDialogModeCreateFolder ? @"Enter a folder name."
                                                                       : @"Enter a file name."];
            return;
        }
        if ([name isEqualToString:@"."] || [name isEqualToString:@".."] ||
            [name containsString:@"/"] || [name containsString:@":"] ||
            [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location !=
                NSNotFound) {
            [self showError:@"Use a name without slashes or colons."];
            return;
        }
        NSURL* parentUrl = _directoryUrl;
        if (_selectedIndex >= 0 && _selectedIndex < (NSInteger)_entries.count &&
            _entries[(NSUInteger)_selectedIndex].directory) {
            parentUrl = _entries[(NSUInteger)_selectedIndex].url;
        }
        NSURL* url = [parentUrl URLByAppendingPathComponent:name isDirectory:YES];
        [_dialogDelegate fileDialog:self didChoosePath:url.path mode:_mode];
        return;
    }
    if (_fileName.length == 0) {
        [self showError:@"Enter a file name."];
        return;
    }
    NSString* path = [_directoryUrl.path stringByAppendingPathComponent:_fileName];
    [_dialogDelegate fileDialog:self didChoosePath:path mode:_mode];
}

- (void)goToParentDirectory {
    NSURL* parent = [_directoryUrl URLByDeletingLastPathComponent];
    if (_creationRootUrl != nil &&
        [parent.path isEqualToString:[[_creationRootUrl URLByDeletingLastPathComponent] path]]) {
        return;
    }
    if (parent != nil && ![parent.path isEqualToString:_directoryUrl.path]) {
        _directoryUrl = parent;
        [self reloadEntries];
    }
}

- (void)keyDown:(NSEvent*)event {
    if (event.keyCode == 53) {
        [_dialogDelegate fileDialogDidCancel:self];
    } else if (event.keyCode == 36 || event.keyCode == 76) {
        [self confirm];
    } else if ([self requiresName] && _editingFileName && event.keyCode == 51 &&
               _fileName.length > 0) {
        [_fileName
            deleteCharactersInRange:[_fileName
                                        rangeOfComposedCharacterSequenceAtIndex:_fileName.length -
                                                                                1]];
        _errorMessage = nil;
        self.needsDisplay = YES;
    } else if (!_editingFileName && event.keyCode == 126 && _selectedIndex > 0) {
        --_selectedIndex;
        self.needsDisplay = YES;
    } else if (!_editingFileName && event.keyCode == 125 &&
               _selectedIndex + 1 < (NSInteger)_entries.count) {
        ++_selectedIndex;
        self.needsDisplay = YES;
    } else {
        NSString* characters = event.characters;
        if ([self requiresName] && _editingFileName && characters.length > 0 &&
            [characters characterAtIndex:0] >= 0x20 &&
            (event.modifierFlags & NSEventModifierFlagCommand) == 0) {
            [_fileName appendString:characters];
            _errorMessage = nil;
            self.needsDisplay = YES;
        } else {
            [super keyDown:event];
        }
    }
}

- (void)mouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(point, _upRect)) {
        [self goToParentDirectory];
    } else if (NSPointInRect(point, _cancelRect)) {
        [_dialogDelegate fileDialogDidCancel:self];
    } else if (NSPointInRect(point, _confirmRect)) {
        [self confirm];
    } else if ([self requiresName] && NSPointInRect(point, _nameFieldRect)) {
        _editingFileName = YES;
        self.needsDisplay = YES;
    } else {
        NSInteger index = [self entryIndexAtPoint:point];
        if (index >= 0) {
            _selectedIndex = index;
            _editingFileName = _mode == KineticFileDialogModeCreateFolder ||
                               _mode == KineticFileDialogModeCreateFile;
            if (event.clickCount == 2) {
                [self openSelectedEntry];
            } else if (_mode == KineticFileDialogModeSave &&
                       !_entries[(NSUInteger)index].directory) {
                [_fileName setString:_entries[(NSUInteger)index].name];
            }
            self.needsDisplay = YES;
        }
    }
}

- (void)rightMouseDown:(NSEvent*)event {
    [self layoutRects];
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(point, _panelRect)) {
        return;
    }
    if ([self requiresName] && NSPointInRect(point, _nameFieldRect)) {
        NSString* pasted = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
        [KineticContextMenu
            showInView:self
               atPoint:point
                 items:@[
                     @{@"title" : @"Copy Name", @"enabled" : @(_fileName.length > 0)},
                     @{@"title" : @"Paste", @"enabled" : @(pasted.length > 0)},
                     @{@"title" : @"Clear", @"enabled" : @(_fileName.length > 0)}
                 ]
               handler:^(NSUInteger selected) {
                 if (selected == 0) {
                     [NSPasteboard.generalPasteboard clearContents];
                     [NSPasteboard.generalPasteboard setString:_fileName
                                                       forType:NSPasteboardTypeString];
                 } else if (selected == 1) {
                     NSString* oneLine = [[pasted
                         componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
                         componentsJoinedByString:@" "];
                     [_fileName appendString:oneLine];
                 } else {
                     [_fileName setString:@""];
                 }
                 _editingFileName = YES;
                 self.needsDisplay = YES;
               }];
        return;
    }
    NSInteger index = [self entryIndexAtPoint:point];
    NSURL* url = index >= 0 ? _entries[(NSUInteger)index].url : _directoryUrl;
    BOOL directory = index < 0 || _entries[(NSUInteger)index].directory;
    if (index >= 0) {
        _selectedIndex = index;
        self.needsDisplay = YES;
    }
    NSMutableArray<NSDictionary<NSString*, id>*>* items = [NSMutableArray array];
    if (index >= 0) {
        [items addObject:@{
            @"title" : directory ? @"Open Folder" : @"Select File",
            @"enabled" : @(directory || _mode == KineticFileDialogModeOpen ||
                           _mode == KineticFileDialogModeSave)
        }];
    }
    [items addObject:@{@"title" : index >= 0 ? @"Copy Path" : @"Copy Folder Path"}];
    NSUInteger copyIndex = items.count - 1;
    [KineticContextMenu showInView:self
                           atPoint:point
                             items:items
                           handler:^(NSUInteger selected) {
                             if (selected == copyIndex) {
                                 [NSPasteboard.generalPasteboard clearContents];
                                 [NSPasteboard.generalPasteboard setString:url.path
                                                                   forType:NSPasteboardTypeString];
                             } else if (index >= 0) {
                                 [self openSelectedEntry];
                             }
                           }];
}

- (void)scrollWheel:(NSEvent*)event {
    _scrollOffset =
        MIN([self maximumScrollOffset], MAX(0.0, _scrollOffset - event.scrollingDeltaY));
    self.needsDisplay = YES;
}

- (void)updateTrackingAreas {
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:_trackingArea];
    [super updateTrackingAreas];
}

- (void)mouseMoved:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger hovered = NSPointInRect(point, _cancelRect)    ? 0
                        : NSPointInRect(point, _confirmRect) ? 1
                                                             : -1;
    if (hovered != _hoveredButton) {
        _hoveredButton = hovered;
        self.needsDisplay = YES;
    }
}

@end
