#import "editorView.h"
#import "settingsPanel.h"
#import "theme.h"
#import "utilityPanel.h"

#import "activityBar.h"
#import "contextMenu.h"
#import "editorStructure.h"
#import "pluginBrowser.h"
#import "syntaxHighlight.h"
#import "tween.h"

#include "kineticBackend.h"
#include "workspaceSearch.h"

#include <cmath>

namespace {

constexpr CGFloat kFirstLineY = 84.0;
constexpr CGFloat kTextOriginX = 92.0;
constexpr CGFloat kContextMenuWidth = 196.0;
constexpr CGFloat kContextMenuRowHeight = 27.0;
constexpr CGFloat kContextMenuPadding = 8.0;
constexpr CGFloat kContextMenuSeparatorHeight = 7.0;
constexpr CGFloat kTabBarY = 34.0;
constexpr CGFloat kTabBarHeight = 34.0;
constexpr CGFloat kPreferredTabWidth = 148.0;
constexpr CGFloat kMinimumTabWidth = 92.0;
constexpr CGFloat kSearchPopoverWidth = 354.0;

enum class EditorMenuCommand : NSInteger {
    undo,
    redo,
    cut,
    copy,
    paste,
    selectAll,
};

NSColor* editorColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha = 1.0) {
    return kineticThemeColor(red, green, blue, alpha);
}

NSColor* syntaxColor(KineticSyntaxKind kind) {
    switch (kind) {
    case KineticSyntaxKindKeyword:
    case KineticSyntaxKindDirective:
        return editorColor(118, 170, 250);
    case KineticSyntaxKindString:
        return editorColor(167, 211, 172);
    case KineticSyntaxKindComment:
        return editorColor(133, 149, 169);
    case KineticSyntaxKindNumber:
        return editorColor(245, 169, 112);
    case KineticSyntaxKindConstant:
        return editorColor(202, 171, 233);
    case KineticSyntaxKindType:
        return editorColor(115, 199, 209);
    case KineticSyntaxKindFunction:
        return editorColor(208, 221, 246);
    case KineticSyntaxKindVariable:
        return editorColor(247, 183, 134);
    case KineticSyntaxKindKey:
        return editorColor(142, 190, 248);
    }
}

} // namespace

@interface KineticEditorView () <KineticActivityBarDelegate, KineticSearchPopoverDelegate,
                                 KineticPluginBrowserDelegate> {
    NSMutableString* _text;
    KineticDocument* _document;
    NSUInteger _caretIndex;
    NSUInteger _selectionAnchor;
    NSTrackingArea* _trackingArea;
    NSInteger _hoveredTabIndex;
    NSInteger _hoveredTabCloseIndex;
    NSUInteger _hoveredDiagnosticIndex;
    BOOL _draggingSelection;
    BOOL _contextMenuVisible;
    NSInteger _contextMenuHoveredIndex;
    NSRect _contextMenuFrame;
    KineticActivityBar* _activityBar;
    KineticPluginBrowser* _pluginBrowser;
    KineticSearchPopover* _searchPopover;
    BOOL _searchOpen;
    BOOL _searchAnimating;
    BOOL _searchClosePending;
    BOOL _searchReopenPending;
    BOOL _dirty;
    NSURL* _fileUrl;
    CGFloat _verticalScroll;
    CGFloat _horizontalScroll;
    CGFloat _fontSize;
    CGFloat _lineHeight;
    CGFloat _letterSpacing;
    NSString* _fontName;
    NSString* _canvasColorHex;
    NSColor* _canvasColor;
    NSUInteger _tabWidth;
    BOOL _insertTabs;
    BOOL _autoIndent;
    BOOL _indentUnitNavigation;
    BOOL _showIndentGuides;
    BOOL _autoPairs;
    BOOL _workspacePlaceholder;
    BOOL _autocompleteEnabled;
    NSUInteger _autocompleteMinPrefix;
    NSUInteger _autocompleteMaxResults;
    NSArray<NSDictionary<NSString*, NSString*>*>* _completionItems;
    NSUInteger _completionPrefixStart;
    NSInteger _completionSelectedIndex;
    NSTimer* _completionPollTimer;
    NSUInteger _completionPollCount;
    KineticSettingsPanel* _settingsPanel;
    KineticUtilityPanel* _utilityPanel;
    BOOL _motionEnabled;
    CGFloat _motionDuration;
    BOOL _smoothCaret;
    CGFloat _caretDuration;
    CGFloat _caretStretch;
    NSPoint _caretCorners[4];
    NSPoint _caretStarts[4];
    NSRect _caretTarget;
    BOOL _caretPositionValid;
    NSTimeInterval _caretStartTime;
    NSTimer* _caretTimer;
    BOOL _showCurrentLine;
    BOOL _showDiagnostics;
    CGFloat _preferredTabWidth;
    NSString* _appPackageStatus;
    NSArray<NSArray<NSDictionary<NSString*, id>*>*>* _syntaxTokens;
    NSArray<NSDictionary<NSString*, id>*>* _diagnostics;
    BOOL _syntaxNeedsUpdate;
    BOOL _syntaxHighlighting;
    BOOL _showLineNumbers;
    BOOL _showScrollIndicators;
    BOOL _naturalScrolling;
    BOOL _settingsVisible;
    BOOL _pluginsVisible;
    NSURL* _workspaceUrl;
    NSString* _documentTitle;
    NSArray<NSString*>* _tabTitles;
    NSIndexSet* _dirtyTabIndexes;
    NSUInteger _activeTabIndex;
}
@end

@implementation KineticEditorView

@synthesize workspacePlaceholder = _workspacePlaceholder;

- (instancetype)initWithFrame:(NSRect)frameRect {
    return [self initWithFrame:frameRect contents:@"" fileUrl:nil];
}

- (instancetype)initWithFrame:(NSRect)frameRect
                     contents:(NSString*)contents
                      fileUrl:(NSURL*)fileUrl {
    self = [super initWithFrame:frameRect];
    if (self) {
        _text = [[NSMutableString alloc] initWithString:contents ?: @""];
        NSData* initialBytes = [_text dataUsingEncoding:NSUTF8StringEncoding];
        _document = kineticDocumentCreate((const uint8_t*)initialBytes.bytes, initialBytes.length);
        _caretIndex = 0;
        _selectionAnchor = 0;
        _hoveredTabIndex = -1;
        _hoveredTabCloseIndex = -1;
        _hoveredDiagnosticIndex = NSNotFound;
        _draggingSelection = NO;
        _contextMenuVisible = NO;
        _contextMenuHoveredIndex = -1;
        _contextMenuFrame = NSZeroRect;
        _dirty = NO;
        _fileUrl = fileUrl;
        _documentTitle = fileUrl.lastPathComponent ?: @"Untitled-1";
        _tabTitles = @[ _documentTitle ];
        _dirtyTabIndexes = [NSIndexSet indexSet];
        _activeTabIndex = 0;
        _verticalScroll = 0.0;
        _horizontalScroll = 0.0;
        _fontSize = 13.0;
        _lineHeight = 20.0;
        _letterSpacing = 0.0;
        _fontName = @"";
        _canvasColorHex = @"#2F3947";
        _canvasColor = nil;
        KineticIndentationConfig indentationConfig = {};
        if (kineticIndentationReadConfig(&indentationConfig) != 0) {
            indentationConfig = {4, false, true, true, true};
        }
        _tabWidth = indentationConfig.tabWidth;
        _insertTabs = indentationConfig.insertTabs;
        _autoIndent = indentationConfig.autoIndent;
        _indentUnitNavigation = indentationConfig.indentUnitNavigation;
        _showIndentGuides = indentationConfig.showIndentGuides;
        _autoPairs = YES;
        KineticCompletionConfig completionConfig = {};
        if (kineticCompletionReadConfig(&completionConfig) != 0) {
            completionConfig = {true, 2, 8};
        }
        _autocompleteEnabled = completionConfig.enabled;
        _autocompleteMinPrefix = completionConfig.minPrefix;
        _autocompleteMaxResults = completionConfig.maxResults;
        _completionItems = @[];
        _completionSelectedIndex = 0;
        _motionEnabled = YES;
        _motionDuration = 180;
        _smoothCaret = NO;
        _caretDuration = 120;
        _caretStretch = 0.6;
        _showDiagnostics = YES;
        _preferredTabWidth = kPreferredTabWidth;
        _appPackageStatus = @"Application updates are manual.";
        _syntaxNeedsUpdate = YES;
        _syntaxHighlighting = YES;
        _showLineNumbers = YES;
        _showScrollIndicators = YES;
        _naturalScrolling = YES;
        _settingsVisible = NO;
        _pluginsVisible = NO;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _activityBar = [[KineticActivityBar alloc]
            initWithFrame:NSMakeRect(0.0, 68.0, KineticActivityBar.railWidth,
                                     MAX(0.0, NSHeight(frameRect) - 68.0))];
        _activityBar.delegate = self;
        _activityBar.documentTitle = _documentTitle;
        [self addSubview:_activityBar];
        _pluginBrowser = [[KineticPluginBrowser alloc]
            initWithFrame:NSMakeRect(KineticActivityBar.railWidth, 68.0,
                                     MAX(1.0, NSWidth(frameRect) - KineticActivityBar.railWidth),
                                     MAX(1.0, NSHeight(frameRect) - 68.0))];
        _pluginBrowser.delegate = self;
        _pluginBrowser.hidden = YES;
        [self updateWorkspaceLayout];
        _settingsPanel = [[KineticSettingsPanel alloc] initWithFrame:self.bounds];
        __weak KineticEditorView* weakSelf = self;
        _settingsPanel.readNumber = ^double(NSString* property) {
          double value = 0;
          [weakSelf getPluginNumber:&value property:property];
          return value;
        };
        _settingsPanel.writeNumber = ^BOOL(NSString* property, double value) {
          KineticEditorView* editor = weakSelf;
          if (![editor setPluginNumber:value property:property])
              return NO;
          [editor.commandHandler editorSettingDidChange:property value:value];
          if ([property hasPrefix:@"editor.indentation."]) {
              KineticIndentationConfig config = {
                  (uint32_t)editor->_tabWidth, (bool)editor->_insertTabs, (bool)editor->_autoIndent,
                  (bool)editor->_indentUnitNavigation, (bool)editor->_showIndentGuides};
              return kineticIndentationWriteConfig(&config) == 0;
          }
          if ([property hasPrefix:@"editor.autocomplete."]) {
              KineticCompletionConfig config = {editor->_autocompleteEnabled,
                                                (uint32_t)editor->_autocompleteMinPrefix,
                                                (uint32_t)editor->_autocompleteMaxResults};
              return kineticCompletionWriteConfig(&config) == 0;
          }
          return [property isEqualToString:@"interface.theme"] ||
                 kineticPreferenceWrite(property.UTF8String, value);
        };
        _settingsPanel.applicationAction = ^(NSString* action) {
          [weakSelf.commandHandler manageApplication:action];
        };
        for (NSDictionary* setting in kineticSettingsRows()) {
            NSString* key = setting[@"key"];
            if ([key hasPrefix:@"editor.indentation."] || [key hasPrefix:@"editor.autocomplete."] ||
                [key isEqualToString:@"interface.theme"])
                continue;
            double value = 0;
            if (kineticPreferenceRead(key.UTF8String, &value))
                [self setPluginNumber:value property:key];
        }
        _searchPopover = [[KineticSearchPopover alloc]
            initWithFrame:NSMakeRect(MAX(8.0, NSWidth(frameRect) - kSearchPopoverWidth - 12.0),
                                     38.0, kSearchPopoverWidth, 165.0)];
        _searchPopover.delegate = self;
        _searchPopover.hidden = YES;
        _searchPopover.autoresizingMask = NSViewMinXMargin;
        [self addSubview:_searchPopover];
    }
    return self;
}

- (void)dealloc {
    [_caretTimer invalidate];
    [_completionPollTimer invalidate];
    kineticDocumentDestroy(_document);
}

- (NSString*)documentText {
    return [_text copy];
}

- (NSURL*)fileUrl {
    return _fileUrl;
}

- (void)setFileUrl:(NSURL*)fileUrl {
    _fileUrl = fileUrl;
    _syntaxNeedsUpdate = YES;
    if (fileUrl != nil) {
        self.documentTitle = fileUrl.lastPathComponent;
    }
    self.needsDisplay = YES;
}

- (void)setDocumentTitle:(NSString*)documentTitle {
    _documentTitle = [documentTitle copy];
    _syntaxNeedsUpdate = YES;
    _activityBar.documentTitle = _documentTitle;
    self.needsDisplay = YES;
}

- (NSString*)documentTitle {
    return _documentTitle;
}

- (void)setTabTitles:(NSArray<NSString*>*)tabTitles {
    _tabTitles = [tabTitles copy];
    [self updateWorkspaceLayout];
    self.needsDisplay = YES;
}

- (NSArray<NSString*>*)tabTitles {
    return _tabTitles;
}

- (void)setDirtyTabIndexes:(NSIndexSet*)dirtyTabIndexes {
    _dirtyTabIndexes = [dirtyTabIndexes copy];
    self.needsDisplay = YES;
}

- (NSIndexSet*)dirtyTabIndexes {
    return _dirtyTabIndexes;
}

- (void)setActiveTabIndex:(NSUInteger)activeTabIndex {
    _activeTabIndex = activeTabIndex;
    self.needsDisplay = YES;
}

- (NSUInteger)activeTabIndex {
    return _activeTabIndex;
}

- (NSURL*)workspaceUrl {
    return _workspaceUrl;
}

- (void)setWorkspaceUrl:(NSURL*)workspaceUrl {
    _workspaceUrl = workspaceUrl;
    _activityBar.workspaceUrl = workspaceUrl;
    _searchPopover.projectAvailable = workspaceUrl != nil;
}

- (BOOL)dirty {
    return _dirty;
}

- (KineticActivitySection)activeActivitySection {
    return _activityBar.activeSection;
}

- (NSDictionary*)workspaceUiState {
    return _activityBar.workspaceUiState;
}

- (NSDictionary*)searchUiState {
    NSMutableDictionary* state = [_searchPopover.searchState mutableCopy];
    state[@"open"] = @(_searchOpen);
    return state;
}

- (KineticSearchScope)searchScope {
    return _searchPopover.scope;
}

- (BOOL)searchOpen {
    return _searchOpen;
}

- (void)applyWorkspaceUiState:(NSDictionary*)state {
    [_activityBar applyWorkspaceUiState:state];
}

- (void)applySearchUiState:(NSDictionary*)state {
    [_searchPopover applySearchState:state];
    _searchPopover.projectAvailable = _workspaceUrl != nil;
    _searchOpen = [state[@"open"] boolValue];
    _searchPopover.hidden = !_searchOpen;
    _searchPopover.alphaValue = 1.0;
    _searchPopover.frame = NSMakeRect(MAX(8.0, NSWidth(self.bounds) - kSearchPopoverWidth - 12.0),
                                      38.0, kSearchPopoverWidth, _searchPopover.preferredHeight);
    if (_searchPopover.scope == KineticSearchScopeFile) {
        [self refreshFileSearch];
    }
    self.needsDisplay = YES;
}

- (void)applySearchResults:(NSArray<NSDictionary*>*)results
                   loading:(BOOL)loading
                 truncated:(BOOL)truncated {
    [_searchPopover applyResults:results loading:loading truncated:truncated];
    [self resizeSearchPopover];
}

- (void)focusWorkspaceSearch {
    [_searchPopover selectScope:KineticSearchScopeProject];
    [self openSearch];
}

- (void)focusFileSearch {
    [_searchPopover selectScope:KineticSearchScopeFile];
    [self openSearch];
}

- (void)toggleFileSearch {
    if (_searchOpen) {
        [self closeSearch];
    } else {
        [self focusFileSearch];
    }
}

- (void)focusSearchQuery {
    if (_searchOpen) {
        [_searchPopover focusQuery];
    }
}

- (void)refreshFileSearch {
    if (_searchPopover.scope != KineticSearchScopeFile) {
        return;
    }
    BOOL truncated = NO;
    NSArray<NSDictionary*>* results =
        kineticSearchText(_text, _searchPopover.query, _searchPopover.matchCase, 300, &truncated);
    [_searchPopover applyResults:results loading:NO truncated:truncated];
    [self resizeSearchPopover];
}

- (void)resizeSearchPopover {
    if (!_searchOpen || _searchAnimating) {
        return;
    }
    NSRect frame = _searchPopover.frame;
    frame.size.height = _searchPopover.preferredHeight;
    _searchPopover.frame = frame;
}

- (void)openSearch {
    if (_searchAnimating) {
        if (_searchOpen) {
            _searchClosePending = NO;
        } else {
            _searchReopenPending = YES;
        }
        return;
    }
    if (!_searchOpen && !_searchAnimating) {
        _searchOpen = YES;
        [self.commandHandler searchVisibilityDidChange:YES];
        _searchAnimating = YES;
        NSRect finalFrame = NSMakeRect(MAX(8.0, NSWidth(self.bounds) - kSearchPopoverWidth - 12.0),
                                       38.0, kSearchPopoverWidth, _searchPopover.preferredHeight);
        _searchPopover.frame = NSMakeRect(NSMinX(finalFrame), 33.0, NSWidth(finalFrame), 26.0);
        _searchPopover.alphaValue = 0.0;
        _searchPopover.hidden = NO;
        [KineticTween animateView:_searchPopover
                          toFrame:finalFrame
                          toAlpha:1.0
                         duration:0.18
                       completion:^{
                         self->_searchAnimating = NO;
                         [self resizeSearchPopover];
                         if (self->_searchClosePending) {
                             self->_searchClosePending = NO;
                             [self closeSearch];
                         }
                       }];
    }
    [_searchPopover focusQuery];
    self.needsDisplay = YES;
}

- (void)closeSearch {
    if (_searchAnimating) {
        if (_searchOpen) {
            _searchClosePending = YES;
        } else {
            _searchReopenPending = NO;
        }
        return;
    }
    if (!_searchOpen) {
        return;
    }
    _searchOpen = NO;
    [self.commandHandler searchVisibilityDidChange:NO];
    _searchAnimating = YES;
    NSRect closingFrame =
        NSMakeRect(NSMinX(_searchPopover.frame), 33.0, NSWidth(_searchPopover.frame), 26.0);
    [KineticTween animateView:_searchPopover
                      toFrame:closingFrame
                      toAlpha:0.0
                     duration:0.15
                   completion:^{
                     self->_searchPopover.hidden = YES;
                     self->_searchAnimating = NO;
                     if (self->_searchReopenPending) {
                         self->_searchReopenPending = NO;
                         [self openSearch];
                     }
                   }];
    [self.window makeFirstResponder:self];
    self.needsDisplay = YES;
}

- (void)revealLine:(NSUInteger)line column:(NSUInteger)column length:(NSUInteger)length {
    NSArray<NSString*>* lines = [self documentLines];
    NSUInteger targetLine = MIN(MAX(line, 1), lines.count) - 1;
    NSUInteger index = 0;
    for (NSUInteger row = 0; row < targetLine; ++row) {
        index += lines[row].length + 1;
    }
    NSUInteger targetColumn = MIN(MAX(column, 1) - 1, lines[targetLine].length);
    index += targetColumn;
    _selectionAnchor = index;
    _caretIndex = index + MIN(length, lines[targetLine].length - targetColumn);
    [self ensureCaretVisible];
    self.needsDisplay = YES;
}

- (void)revealCreatedFolderAtUrl:(NSURL*)url {
    [_activityBar revealCreatedFolderAtUrl:url];
}

- (void)revealCreatedFileAtUrl:(NSURL*)url {
    [_activityBar revealCreatedFileAtUrl:url];
}

- (void)closeUtilityPanel {
    _settingsVisible = NO;
    _pluginsVisible = NO;
    [_utilityPanel
        dismissAnimated:_motionEnabled &&
                        !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion
               duration:_motionDuration / 1000.0];
    _utilityPanel = nil;
    [self.window makeFirstResponder:self];
    self.needsDisplay = YES;
}

- (BOOL)closeUtilityPanelIfOpen {
    if (!_utilityPanel)
        return NO;
    [self closeUtilityPanel];
    return YES;
}

- (void)setActivitySection:(KineticActivitySection)section animated:(BOOL)animated {
    if (section != KineticActivitySectionSettings && section != KineticActivitySectionPlugins) {
        if (_utilityPanel)
            [self closeUtilityPanel];
        [_activityBar activateSection:section animated:animated];
        return;
    }
    [_utilityPanel removeFromSuperview];
    _settingsVisible = section == KineticActivitySectionSettings;
    _pluginsVisible = !_settingsVisible;
    [self closeCompletions];
    NSView* content = _pluginsVisible ? (NSView*)_pluginBrowser : (NSView*)_settingsPanel;
    _pluginBrowser.hidden = NO;
    _utilityPanel =
        [[KineticUtilityPanel alloc] initWithFrame:NSMakeRect(0, kTabBarY, NSWidth(self.bounds),
                                                              NSHeight(self.bounds) - kTabBarY)
                                           content:content];
    __weak KineticEditorView* weakSelf = self;
    _utilityPanel.closeHandler = ^{
      [weakSelf closeUtilityPanel];
    };
    [self addSubview:_utilityPanel positioned:NSWindowAbove relativeTo:nil];
    [_utilityPanel
        presentAnimated:animated && _motionEnabled &&
                        !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion
               duration:_motionDuration / 1000.0];
    self.needsDisplay = YES;
}

- (void)markSaved {
    kineticDocumentMarkSaved(_document);
    _dirty = kineticDocumentIsDirty(_document);
    self.needsDisplay = YES;
}

- (BOOL)setPluginNumber:(double)value property:(NSString*)property {
    if (!std::isfinite(value)) {
        return NO;
    }
    if ([property isEqualToString:@"interface.theme"] && value >= 0 && value <= 2 &&
        floor(value) == value) {
        kineticSetThemeName(@[ @"kinetic-dark", @"midnight", @"graphite" ][(NSUInteger)value]);
        kineticRefreshThemeInView(self.window.contentView ?: self);
    } else if ([property isEqualToString:@"editor.text.fontPreset"] && value >= 0 && value <= 3 &&
               floor(value) == value) {
        _fontName = @[ @"", @"Menlo", @"Monaco", @"Courier" ][(NSUInteger)value];
    } else if ([property isEqualToString:@"interface.motion.enabled"] &&
               (value == 0 || value == 1)) {
        _motionEnabled = value == 1;
    } else if ([property isEqualToString:@"interface.motion.duration"] && value >= 80 &&
               value <= 400) {
        _motionDuration = value;
    } else if ([property isEqualToString:@"editor.caret.smooth"] && (value == 0 || value == 1)) {
        _smoothCaret = value == 1;
    } else if ([property isEqualToString:@"editor.caret.duration"] && value >= 40 && value <= 300) {
        _caretDuration = value;
    } else if ([property isEqualToString:@"editor.caret.stretch"] && value >= 0 && value <= 1) {
        _caretStretch = value;
    } else if ([property isEqualToString:@"editor.currentLine.enabled"] &&
               (value == 0 || value == 1)) {
        _showCurrentLine = value == 1;
    } else if ([property isEqualToString:@"editor.diagnostics.enabled"] &&
               (value == 0 || value == 1)) {
        _showDiagnostics = value == 1;
        _hoveredDiagnosticIndex = NSNotFound;
    } else if ([property isEqualToString:@"editor.tabs.preferredWidth"] && value >= 100 &&
               value <= 240) {
        _preferredTabWidth = value;
    } else if ([property isEqualToString:@"editor.text.letterSpacing"] && value >= -2.0 &&
               value <= 8.0) {
        _letterSpacing = value;
    } else if ([property isEqualToString:@"editor.text.fontSize"] && value >= 8.0 &&
               value <= 28.0) {
        _fontSize = value;
    } else if ([property isEqualToString:@"editor.text.lineHeight"] && value >= 14.0 &&
               value <= 40.0) {
        _lineHeight = value;
    } else if ([property isEqualToString:@"editor.indentation.tabWidth"] && value >= 1.0 &&
               value <= 16.0 && floor(value) == value) {
        _tabWidth = (NSUInteger)value;
    } else if ([property isEqualToString:@"editor.indentation.insertTabs"] &&
               (value == 0.0 || value == 1.0)) {
        _insertTabs = value == 1.0;
    } else if ([property isEqualToString:@"editor.indentation.unitNavigation"] &&
               (value == 0.0 || value == 1.0)) {
        _indentUnitNavigation = value == 1.0;
    } else if ([property isEqualToString:@"editor.indentation.guides"] &&
               (value == 0.0 || value == 1.0)) {
        _showIndentGuides = value == 1.0;
    } else if ([property isEqualToString:@"editor.syntax.enabled"] &&
               (value == 0.0 || value == 1.0)) {
        _syntaxHighlighting = value == 1.0;
    } else if ([property isEqualToString:@"editor.gutter.lineNumbers"] &&
               (value == 0.0 || value == 1.0)) {
        _showLineNumbers = value == 1.0;
    } else if ([property isEqualToString:@"editor.scroll.indicators"] &&
               (value == 0.0 || value == 1.0)) {
        _showScrollIndicators = value == 1.0;
    } else if ([property isEqualToString:@"editor.scroll.natural"] &&
               (value == 0.0 || value == 1.0)) {
        _naturalScrolling = value == 1.0;
    } else if ([property isEqualToString:@"editor.indentation.autoIndent"] &&
               (value == 0.0 || value == 1.0)) {
        _autoIndent = value == 1.0;
    } else if ([property isEqualToString:@"editor.delimiters.autoPairs"] &&
               (value == 0.0 || value == 1.0)) {
        _autoPairs = value == 1.0;
    } else if ([property isEqualToString:@"editor.autocomplete.enabled"] &&
               (value == 0.0 || value == 1.0)) {
        _autocompleteEnabled = value == 1.0;
        if (!_autocompleteEnabled) {
            _completionItems = @[];
        }
    } else if ([property isEqualToString:@"editor.autocomplete.minPrefix"] && value >= 1.0 &&
               value <= 8.0 && floor(value) == value) {
        _autocompleteMinPrefix = (NSUInteger)value;
    } else if ([property isEqualToString:@"editor.autocomplete.maxResults"] && value >= 1.0 &&
               value <= 32.0 && floor(value) == value) {
        _autocompleteMaxResults = (NSUInteger)value;
    } else {
        return NO;
    }
    [self clampScroll];
    self.needsDisplay = YES;
    return YES;
}

- (BOOL)getPluginNumber:(double*)value property:(NSString*)property {
    if (value == nullptr) {
        return NO;
    }
    if ([property isEqualToString:@"interface.theme"]) {
        NSUInteger index =
            [@[ @"kinetic-dark", @"midnight", @"graphite" ] indexOfObject:kineticThemeName()];
        *value = index == NSNotFound ? 0 : index;
    } else if ([property isEqualToString:@"editor.text.fontPreset"]) {
        NSUInteger index =
            [@[ @"", @"Menlo", @"Monaco", @"Courier" ] indexOfObject:_fontName ?: @""];
        *value = index == NSNotFound ? 0 : index;
    } else if ([property isEqualToString:@"interface.motion.enabled"]) {
        *value = _motionEnabled;
    } else if ([property isEqualToString:@"interface.motion.duration"]) {
        *value = _motionDuration;
    } else if ([property isEqualToString:@"editor.caret.smooth"]) {
        *value = _smoothCaret;
    } else if ([property isEqualToString:@"editor.caret.duration"]) {
        *value = _caretDuration;
    } else if ([property isEqualToString:@"editor.caret.stretch"]) {
        *value = _caretStretch;
    } else if ([property isEqualToString:@"editor.currentLine.enabled"]) {
        *value = _showCurrentLine;
    } else if ([property isEqualToString:@"editor.diagnostics.enabled"]) {
        *value = _showDiagnostics;
    } else if ([property isEqualToString:@"editor.tabs.preferredWidth"]) {
        *value = _preferredTabWidth;
    } else if ([property isEqualToString:@"editor.text.letterSpacing"]) {
        *value = _letterSpacing;
    } else if ([property isEqualToString:@"editor.text.fontSize"]) {
        *value = _fontSize;
    } else if ([property isEqualToString:@"editor.text.lineHeight"]) {
        *value = _lineHeight;
    } else if ([property isEqualToString:@"editor.indentation.tabWidth"]) {
        *value = _tabWidth;
    } else if ([property isEqualToString:@"editor.indentation.insertTabs"]) {
        *value = _insertTabs;
    } else if ([property isEqualToString:@"editor.indentation.unitNavigation"]) {
        *value = _indentUnitNavigation;
    } else if ([property isEqualToString:@"editor.indentation.guides"]) {
        *value = _showIndentGuides;
    } else if ([property isEqualToString:@"editor.syntax.enabled"]) {
        *value = _syntaxHighlighting;
    } else if ([property isEqualToString:@"editor.gutter.lineNumbers"]) {
        *value = _showLineNumbers;
    } else if ([property isEqualToString:@"editor.scroll.indicators"]) {
        *value = _showScrollIndicators;
    } else if ([property isEqualToString:@"editor.scroll.natural"]) {
        *value = _naturalScrolling;
    } else if ([property isEqualToString:@"editor.indentation.autoIndent"]) {
        *value = _autoIndent;
    } else if ([property isEqualToString:@"editor.delimiters.autoPairs"]) {
        *value = _autoPairs;
    } else if ([property isEqualToString:@"editor.autocomplete.enabled"]) {
        *value = _autocompleteEnabled;
    } else if ([property isEqualToString:@"editor.autocomplete.minPrefix"]) {
        *value = _autocompleteMinPrefix;
    } else if ([property isEqualToString:@"editor.autocomplete.maxResults"]) {
        *value = _autocompleteMaxResults;
    } else {
        return NO;
    }
    return YES;
}

- (BOOL)setPluginString:(NSString*)value property:(NSString*)property {
    if ([property isEqualToString:@"editor.text.fontFamily"]) {
        if (value.length > 128 || (value.length > 0 && [NSFont fontWithName:value
                                                                       size:_fontSize] == nil)) {
            return NO;
        }
        _fontName = [value copy];
    } else if ([property isEqualToString:@"editor.canvas.background"]) {
        if (value.length != 7 || ![value hasPrefix:@"#"] ||
            [[value substringFromIndex:1]
                rangeOfCharacterFromSet:
                    [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"]
                        .invertedSet]
                    .location != NSNotFound) {
            return NO;
        }
        unsigned int rgb = 0;
        [[NSScanner scannerWithString:[value substringFromIndex:1]] scanHexInt:&rgb];
        _canvasColorHex = [value.uppercaseString copy];
        _canvasColor = [NSColor colorWithSRGBRed:((rgb >> 16) & 0xff) / 255.0
                                           green:((rgb >> 8) & 0xff) / 255.0
                                            blue:(rgb & 0xff) / 255.0
                                           alpha:0.9];
    } else {
        return NO;
    }
    self.needsDisplay = YES;
    return YES;
}

- (NSString*)getPluginString:(NSString*)property {
    if ([property isEqualToString:@"editor.text.fontFamily"]) {
        return _fontName;
    }
    if ([property isEqualToString:@"editor.canvas.background"]) {
        return _canvasColorHex;
    }
    return nil;
}

- (NSRange)pluginSelection {
    return [self selectionRange];
}

- (BOOL)setPluginSelection:(NSRange)selection {
    if (selection.location > _text.length || selection.length > _text.length - selection.location) {
        return NO;
    }
    _selectionAnchor = selection.location;
    _caretIndex = NSMaxRange(selection);
    [self ensureCaretVisible];
    self.needsDisplay = YES;
    return YES;
}

- (BOOL)replaceRangeFromPlugin:(NSRange)range withString:(NSString*)text {
    if (range.location > _text.length || range.length > _text.length - range.location) {
        return NO;
    }
    [self recordUndoState];
    if (![self replaceTextInRange:range withString:text]) {
        return NO;
    }
    _caretIndex = range.location + text.length;
    _selectionAnchor = _caretIndex;
    [self updateDirtyState];
    [self ensureCaretVisible];
    self.needsDisplay = YES;
    return YES;
}

- (void)replaceSelectionFromPlugin:(NSString*)text {
    [self replaceSelectionWithString:text];
    [self ensureCaretVisible];
    self.needsDisplay = YES;
}

- (void)setPluginNames:(NSArray<NSString*>*)names
              commands:(NSArray<NSDictionary<NSString*, NSString*>*>*)commands
    configurationError:(NSString*)configurationError {
    _activityBar.pluginNames = names;
    _activityBar.pluginCommands = commands;
    _activityBar.pluginConfigurationError = configurationError;
}

- (void)setPluginPanels:(NSArray<NSDictionary<NSString*, id>*>*)panels {
    _activityBar.pluginPanels = panels;
    _syntaxNeedsUpdate = YES;
    self.needsDisplay = YES;
}

- (void)setCatalogPlugins:(NSArray<NSDictionary<NSString*, id>*>*)plugins status:(NSString*)status {
    _pluginBrowser.plugins = plugins;
    _pluginBrowser.status = status;
}

- (void)setAppPackageStatus:(NSString*)status {
    _appPackageStatus = [status copy];
    _settingsPanel.applicationStatus = status;
    _settingsPanel.needsDisplay = YES;
    self.needsDisplay = YES;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return NO;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (NSUInteger)visibleTabCount {
    return _tabTitles.count;
}

- (CGFloat)workspaceContentY {
    return kTabBarY + ([self visibleTabCount] > 0 ? kTabBarHeight : 0.0);
}

- (void)updateWorkspaceLayout {
    CGFloat top = [self workspaceContentY];
    NSRect railFrame = _activityBar.frame;
    railFrame.origin.y = top;
    railFrame.size.height = MAX(0.0, NSHeight(self.bounds) - top);
    _activityBar.frame = railFrame;
    [self.window invalidateCursorRectsForView:self];
}

- (CGFloat)tabWidth {
    NSUInteger count = MAX((NSUInteger)1, [self visibleTabCount]);
    CGFloat available = MAX(kMinimumTabWidth, NSWidth(self.bounds) - 56.0);
    return MAX(kMinimumTabWidth, MIN(_preferredTabWidth, floor(available / count)));
}

- (NSRect)tabRectAtIndex:(NSUInteger)index {
    return NSMakeRect(index * [self tabWidth], kTabBarY, [self tabWidth], kTabBarHeight);
}

- (NSRect)closeRectAtIndex:(NSUInteger)index {
    NSRect tabRect = [self tabRectAtIndex:index];
    return NSMakeRect(NSMaxX(tabRect) - 27.0, NSMinY(tabRect) + 7.0, 20.0, 20.0);
}

- (NSDictionary<NSAttributedStringKey, id>*)editorTextAttributes {
    NSFont* font = _fontName.length > 0 ? [NSFont fontWithName:_fontName size:_fontSize] : nil;
    return @{
        NSFontAttributeName : font
            ?: [NSFont monospacedSystemFontOfSize:_fontSize weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : editorColor(226, 233, 242),
        NSKernAttributeName : @(_letterSpacing),
    };
}

- (CGFloat)editorContentX {
    return NSMaxX(_activityBar.frame);
}

- (CGFloat)editorTextOriginX {
    return MAX(kTextOriginX, [self editorContentX] + 54.0);
}

- (CGFloat)editorViewportWidth {
    return MAX(1.0, NSWidth(self.bounds) - [self editorTextOriginX] - 18.0);
}

- (NSArray<NSString*>*)documentLines {
    return [_text componentsSeparatedByString:@"\n"];
}

- (NSArray<NSArray<NSDictionary<NSString*, id>*>*>*)syntaxTokensForLines:
    (NSArray<NSString*>*)lines {
    if (!_syntaxHighlighting) {
        return @[];
    }
    if (_syntaxNeedsUpdate) {
        NSString* fileName = _fileUrl.lastPathComponent ?: _documentTitle;
        _syntaxTokens = [self.overlayRenderer pluginSyntaxTokensForLines:lines fileName:fileName]
                            ?: kineticSyntaxTokens(lines, fileName);
        _syntaxNeedsUpdate = NO;
    }
    return _syntaxTokens;
}

- (void)setDiagnostics:(NSArray<NSDictionary<NSString*, id>*>*)diagnostics {
    _diagnostics = [diagnostics copy] ?: @[];
    _hoveredDiagnosticIndex = NSNotFound;
    self.needsDisplay = YES;
}

- (NSArray<NSDictionary<NSString*, id>*>*)diagnostics {
    return _diagnostics;
}

- (NSRect)diagnosticPopoverRectForLine:(NSUInteger)index {
    CGFloat left = [self editorContentX] + 8.0;
    CGFloat width = MIN(420.0, NSWidth(self.bounds) - left - 12.0);
    if (width < 120.0) {
        return NSZeroRect;
    }
    CGFloat y = kFirstLineY + index * _lineHeight - _verticalScroll + _lineHeight + 5.0;
    if (y + 48.0 > NSHeight(self.bounds) - 8.0) {
        y = kFirstLineY + index * _lineHeight - _verticalScroll - 53.0;
    }
    return NSMakeRect(left, y, width, 48.0);
}

- (NSRect)fixRectForLine:(NSUInteger)index diagnostic:(NSDictionary<NSString*, id>*)diagnostic {
    if (![diagnostic[@"fixAvailable"] boolValue]) {
        return NSZeroRect;
    }
    NSRect popover = [self diagnosticPopoverRectForLine:index];
    return NSIsEmptyRect(popover)
               ? NSZeroRect
               : NSMakeRect(NSMaxX(popover) - 45.0, NSMinY(popover) + 13.0, 34.0, 22.0);
}

- (NSRange)selectionRange {
    NSUInteger start = MIN(_selectionAnchor, _caretIndex);
    NSUInteger end = MAX(_selectionAnchor, _caretIndex);
    return NSMakeRange(start, end - start);
}

- (void)updateDirtyState {
    _dirty = kineticDocumentIsDirty(_document);
    _syntaxNeedsUpdate = YES;
    [self.commandHandler editorDocumentDidChange];
    if (_searchOpen && _searchPopover.scope == KineticSearchScopeFile) {
        [self refreshFileSearch];
    }
}

- (void)refreshTextFromBackend {
    uint64_t length = kineticDocumentCopyUtf8(_document, nullptr, 0);
    NSMutableData* bytes = [NSMutableData dataWithLength:(NSUInteger)length + 1];
    kineticDocumentCopyUtf8(_document, (uint8_t*)bytes.mutableBytes, bytes.length);
    NSString* text = [[NSString alloc] initWithBytes:bytes.bytes
                                              length:(NSUInteger)length
                                            encoding:NSUTF8StringEncoding];
    [_text setString:text ?: @""];
    [self updateDirtyState];
    [self ensureCaretVisible];
    self.needsDisplay = YES;
}

- (void)recordUndoState {
    kineticDocumentCheckpoint(_document, _caretIndex, _selectionAnchor);
}

- (void)undoEdit {
    uint64_t caret = 0;
    uint64_t anchor = 0;
    if (kineticDocumentHistoryStep(_document, false, _caretIndex, _selectionAnchor, &caret,
                                   &anchor) == 0) {
        _caretIndex = (NSUInteger)caret;
        _selectionAnchor = (NSUInteger)anchor;
        [self refreshTextFromBackend];
    }
}

- (void)redoEdit {
    uint64_t caret = 0;
    uint64_t anchor = 0;
    if (kineticDocumentHistoryStep(_document, true, _caretIndex, _selectionAnchor, &caret,
                                   &anchor) == 0) {
        _caretIndex = (NSUInteger)caret;
        _selectionAnchor = (NSUInteger)anchor;
        [self refreshTextFromBackend];
    }
}

- (BOOL)replaceTextInRange:(NSRange)range withString:(NSString*)replacement {
    NSData* bytes = [replacement dataUsingEncoding:NSUTF8StringEncoding];
    if (bytes == nil) {
        return NO;
    }
    if (kineticDocumentReplaceUtf8(_document, range.location, range.length,
                                   (const uint8_t*)bytes.bytes, bytes.length) != 0) {
        return NO;
    }
    [_text replaceCharactersInRange:range withString:replacement];
    return YES;
}

- (BOOL)deleteSelection {
    NSRange selection = [self selectionRange];
    if (selection.length == 0) {
        return NO;
    }
    if (![self replaceTextInRange:selection withString:@""]) {
        return NO;
    }
    _caretIndex = selection.location;
    _selectionAnchor = _caretIndex;
    [self updateDirtyState];
    return YES;
}

- (void)replaceSelectionWithString:(NSString*)replacement {
    NSRange selection = [self selectionRange];
    [self recordUndoState];
    if (![self replaceTextInRange:selection withString:replacement]) {
        return;
    }
    _caretIndex = selection.location + replacement.length;
    _selectionAnchor = _caretIndex;
    [self updateDirtyState];
}

- (void)applyStructureEdit:(KineticStructureEdit*)edit {
    if (edit == nil) {
        return;
    }
    if (edit.range.length > 0 || edit.replacement.length > 0) {
        [self recordUndoState];
        if (![self replaceTextInRange:edit.range withString:edit.replacement]) {
            return;
        }
        [self updateDirtyState];
    }
    _selectionAnchor = edit.range.location + edit.anchorOffset;
    _caretIndex = edit.range.location + edit.caretOffset;
}

- (void)copySelection {
    NSRange selection = [self selectionRange];
    if (selection.length == 0) {
        return;
    }
    NSPasteboard* pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:[_text substringWithRange:selection] forType:NSPasteboardTypeString];
}

- (void)cutSelection {
    if ([self selectionRange].length == 0) {
        return;
    }
    [self copySelection];
    [self recordUndoState];
    [self deleteSelection];
}

- (void)pasteText {
    NSString* pastedText = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
    if (pastedText == nil) {
        return;
    }
    [self replaceSelectionWithString:pastedText];
}

- (void)selectAllText {
    _selectionAnchor = 0;
    _caretIndex = _text.length;
    [self ensureCaretVisible];
    self.needsDisplay = YES;
}

- (NSUInteger)previousWordIndexFromIndex:(NSUInteger)index {
    NSCharacterSet* whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSCharacterSet* wordCharacters = [NSCharacterSet alphanumericCharacterSet];
    NSUInteger cursor = index;
    while (cursor > 0 && [whitespace characterIsMember:[_text characterAtIndex:cursor - 1]]) {
        --cursor;
    }
    if (cursor == 0) {
        return 0;
    }
    unichar character = [_text characterAtIndex:cursor - 1];
    BOOL isWord = [wordCharacters characterIsMember:character] || character == '_';
    while (cursor > 0) {
        character = [_text characterAtIndex:cursor - 1];
        BOOL candidateIsWord = [wordCharacters characterIsMember:character] || character == '_';
        if ([whitespace characterIsMember:character] || candidateIsWord != isWord) {
            break;
        }
        --cursor;
    }
    return cursor;
}

- (NSUInteger)nextWordIndexFromIndex:(NSUInteger)index {
    NSCharacterSet* whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSCharacterSet* wordCharacters = [NSCharacterSet alphanumericCharacterSet];
    NSUInteger cursor = index;
    while (cursor < _text.length && [whitespace
                                        characterIsMember:[_text characterAtIndex:cursor]]) {
        ++cursor;
    }
    if (cursor == _text.length) {
        return cursor;
    }
    unichar character = [_text characterAtIndex:cursor];
    BOOL isWord = [wordCharacters characterIsMember:character] || character == '_';
    while (cursor < _text.length) {
        character = [_text characterAtIndex:cursor];
        BOOL candidateIsWord = [wordCharacters characterIsMember:character] || character == '_';
        if ([whitespace characterIsMember:character] || candidateIsWord != isWord) {
            break;
        }
        ++cursor;
    }
    return cursor;
}

- (NSUInteger)lineStartIndexFromIndex:(NSUInteger)index {
    NSRange searchRange = NSMakeRange(0, index);
    NSRange newline = [_text rangeOfString:@"\n" options:NSBackwardsSearch range:searchRange];
    return newline.location == NSNotFound ? 0 : NSMaxRange(newline);
}

- (NSUInteger)lineEndIndexFromIndex:(NSUInteger)index {
    NSRange searchRange = NSMakeRange(index, _text.length - index);
    NSRange newline = [_text rangeOfString:@"\n" options:0 range:searchRange];
    return newline.location == NSNotFound ? _text.length : newline.location;
}

- (NSUInteger)textIndexForPoint:(NSPoint)point {
    NSArray<NSString*>* lines = [self documentLines];
    NSInteger lineIndex = (NSInteger)floor((point.y - kFirstLineY + _verticalScroll) / _lineHeight);
    lineIndex = MIN((NSInteger)lines.count - 1, MAX(0, lineIndex));

    NSUInteger lineStart = 0;
    for (NSInteger index = 0; index < lineIndex; ++index) {
        lineStart += lines[(NSUInteger)index].length + 1;
    }

    NSString* line = lines[(NSUInteger)lineIndex];
    CGFloat targetX = point.x - [self editorTextOriginX] + _horizontalScroll;
    if (targetX <= 0.0 || line.length == 0) {
        return lineStart;
    }

    NSDictionary* attributes = [self editorTextAttributes];
    __block CGFloat consumedWidth = 0.0;
    __block NSUInteger column = line.length;
    [line enumerateSubstringsInRange:NSMakeRange(0, line.length)
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString* substring, NSRange substringRange,
                                       NSRange enclosingRange, BOOL* stop) {
                            (void)enclosingRange;
                            CGFloat glyphWidth = [substring sizeWithAttributes:attributes].width;
                            if (targetX < consumedWidth + glyphWidth * 0.5) {
                                column = substringRange.location;
                                *stop = YES;
                                return;
                            }
                            consumedWidth += glyphWidth;
                          }];
    return lineStart + column;
}

- (CGFloat)maximumVerticalScroll {
    CGFloat viewportHeight = MAX(1.0, NSHeight(self.bounds) - kFirstLineY - 12.0);
    return MAX(0.0, [self documentLines].count * _lineHeight - viewportHeight);
}

- (CGFloat)maximumHorizontalScroll {
    NSDictionary* attributes = [self editorTextAttributes];
    CGFloat widestLine = 0.0;
    for (NSString* line in [self documentLines]) {
        widestLine = MAX(widestLine, [line sizeWithAttributes:attributes].width);
    }
    return MAX(0.0, widestLine - [self editorViewportWidth]);
}

- (void)clampScroll {
    _verticalScroll = MIN([self maximumVerticalScroll], MAX(0.0, _verticalScroll));
    _horizontalScroll = MIN([self maximumHorizontalScroll], MAX(0.0, _horizontalScroll));
}

- (void)getCaretLine:(NSUInteger*)lineOut column:(NSUInteger*)columnOut {
    NSString* beforeCaret = [_text substringToIndex:_caretIndex];
    NSArray<NSString*>* lines = [beforeCaret componentsSeparatedByString:@"\n"];
    *lineOut = lines.count - 1;
    *columnOut = lines.lastObject.length;
}

- (void)ensureCaretVisible {
    NSUInteger line = 0;
    NSUInteger column = 0;
    [self getCaretLine:&line column:&column];
    CGFloat caretY = line * _lineHeight;
    CGFloat viewportHeight = MAX(1.0, NSHeight(self.bounds) - kFirstLineY - 12.0);
    if (caretY < _verticalScroll) {
        _verticalScroll = caretY;
    } else if (caretY + _lineHeight > _verticalScroll + viewportHeight) {
        _verticalScroll = caretY + _lineHeight - viewportHeight;
    }

    NSString* lineText = [self documentLines][line];
    NSString* beforeCaret = [lineText substringToIndex:MIN(column, lineText.length)];
    CGFloat caretX = [beforeCaret sizeWithAttributes:[self editorTextAttributes]].width;
    CGFloat viewportWidth = [self editorViewportWidth];
    if (caretX < _horizontalScroll) {
        _horizontalScroll = caretX;
    } else if (caretX + 10.0 > _horizontalScroll + viewportWidth) {
        _horizontalScroll = caretX + 10.0 - viewportWidth;
    }
    [self clampScroll];
}

- (void)moveCaretVertically:(NSInteger)lineDelta {
    NSArray<NSString*>* lines = [self documentLines];
    NSUInteger line = 0;
    NSUInteger column = 0;
    [self getCaretLine:&line column:&column];
    NSInteger targetLine = MIN((NSInteger)lines.count - 1, MAX(0, (NSInteger)line + lineDelta));
    NSUInteger targetColumn = MIN(column, lines[(NSUInteger)targetLine].length);
    NSUInteger targetIndex = targetColumn;
    for (NSInteger index = 0; index < targetLine; ++index) {
        targetIndex += lines[(NSUInteger)index].length + 1;
    }
    _caretIndex = targetIndex;
}

- (NSArray<NSString*>*)contextMenuTitles {
    return @[ @"Undo", @"Redo", @"Cut", @"Copy", @"Paste", @"Select All" ];
}

- (NSArray<NSString*>*)contextMenuShortcuts {
    return @[ @"⌘Z", @"⇧⌘Z", @"⌘X", @"⌘C", @"⌘V", @"⌘A" ];
}

- (CGFloat)contextMenuRowOffset:(NSInteger)index {
    CGFloat offset = kContextMenuPadding + index * kContextMenuRowHeight;
    if (index >= 2) {
        offset += kContextMenuSeparatorHeight;
    }
    if (index >= 5) {
        offset += kContextMenuSeparatorHeight;
    }
    return offset;
}

- (NSRect)contextMenuRowRect:(NSInteger)index {
    return NSMakeRect(NSMinX(_contextMenuFrame) + 5.0,
                      NSMinY(_contextMenuFrame) + [self contextMenuRowOffset:index],
                      NSWidth(_contextMenuFrame) - 10.0, kContextMenuRowHeight);
}

- (NSInteger)contextMenuIndexAtPoint:(NSPoint)point {
    if (!_contextMenuVisible || !NSPointInRect(point, _contextMenuFrame)) {
        return -1;
    }
    for (NSInteger index = 0; index < (NSInteger)[self contextMenuTitles].count; ++index) {
        if (NSPointInRect(point, [self contextMenuRowRect:index])) {
            return index;
        }
    }
    return -1;
}

- (BOOL)contextMenuItemEnabled:(NSInteger)index {
    switch ((EditorMenuCommand)index) {
    case EditorMenuCommand::undo:
        return kineticDocumentCanUndo(_document);
    case EditorMenuCommand::redo:
        return kineticDocumentCanRedo(_document);
    case EditorMenuCommand::cut:
    case EditorMenuCommand::copy:
        return [self selectionRange].length > 0;
    case EditorMenuCommand::paste:
        return [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString] != nil;
    case EditorMenuCommand::selectAll:
        return _text.length > 0;
    }
    return NO;
}

- (void)performContextMenuItem:(NSInteger)index {
    if (![self contextMenuItemEnabled:index]) {
        return;
    }
    switch ((EditorMenuCommand)index) {
    case EditorMenuCommand::undo:
        [self undoEdit];
        break;
    case EditorMenuCommand::redo:
        [self redoEdit];
        break;
    case EditorMenuCommand::cut:
        [self cutSelection];
        break;
    case EditorMenuCommand::copy:
        [self copySelection];
        break;
    case EditorMenuCommand::paste:
        [self pasteText];
        break;
    case EditorMenuCommand::selectAll:
        [self selectAllText];
        break;
    }
    [self ensureCaretVisible];
    self.needsDisplay = YES;
}

- (void)showContextMenuAtPoint:(NSPoint)point {
    CGFloat menuHeight =
        kContextMenuPadding * 2.0 + kContextMenuRowHeight * 6.0 + kContextMenuSeparatorHeight * 2.0;
    CGFloat x = MIN(point.x, NSWidth(self.bounds) - kContextMenuWidth - 8.0);
    CGFloat y = MIN(point.y, NSHeight(self.bounds) - menuHeight - 8.0);
    x = MAX(8.0, x);
    y = MAX(72.0, y);
    _contextMenuFrame = NSMakeRect(x, y, kContextMenuWidth, menuHeight);
    _contextMenuHoveredIndex = -1;
    _contextMenuVisible = YES;
    [self.window invalidateCursorRectsForView:self];
    self.needsDisplay = YES;
}

- (void)hideContextMenu {
    if (!_contextMenuVisible) {
        return;
    }
    _contextMenuVisible = NO;
    _contextMenuHoveredIndex = -1;
    [self.window invalidateCursorRectsForView:self];
    self.needsDisplay = YES;
}

- (void)drawContextMenu {
    if (!_contextMenuVisible) {
        return;
    }

    NSShadow* shadow = [[NSShadow alloc] init];
    shadow.shadowColor = editorColor(5, 9, 16, 0.55);
    shadow.shadowBlurRadius = 18.0;
    shadow.shadowOffset = NSMakeSize(0.0, 6.0);
    [NSGraphicsContext saveGraphicsState];
    [shadow set];
    [editorColor(35, 43, 55, 0.98) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:_contextMenuFrame xRadius:7.0 yRadius:7.0] fill];
    [NSGraphicsContext restoreGraphicsState];

    [editorColor(75, 90, 111, 0.75) setStroke];
    NSBezierPath* outline = [NSBezierPath bezierPathWithRoundedRect:_contextMenuFrame
                                                            xRadius:7.0
                                                            yRadius:7.0];
    outline.lineWidth = 1.0;
    [outline stroke];

    NSArray<NSString*>* titles = [self contextMenuTitles];
    NSArray<NSString*>* shortcuts = [self contextMenuShortcuts];
    NSDictionary* titleAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : editorColor(226, 233, 242),
    };
    NSDictionary* shortcutAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : editorColor(139, 155, 177),
    };
    NSDictionary* disabledAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : editorColor(107, 119, 137),
    };

    for (NSInteger index = 0; index < (NSInteger)titles.count; ++index) {
        NSRect rowRect = [self contextMenuRowRect:index];
        BOOL enabled = [self contextMenuItemEnabled:index];
        if (enabled && index == _contextMenuHoveredIndex) {
            [editorColor(77, 141, 255, 0.2) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:rowRect xRadius:4.0 yRadius:4.0] fill];
        }
        NSDictionary* attributes = enabled ? titleAttributes : disabledAttributes;
        [titles[(NSUInteger)index]
               drawAtPoint:NSMakePoint(NSMinX(rowRect) + 8.0, NSMinY(rowRect) + 5.5)
            withAttributes:attributes];
        NSSize shortcutSize = [shortcuts[(NSUInteger)index] sizeWithAttributes:shortcutAttributes];
        [shortcuts[(NSUInteger)index]
               drawAtPoint:NSMakePoint(NSMaxX(rowRect) - shortcutSize.width - 8.0,
                                       NSMinY(rowRect) + 6.0)
            withAttributes:enabled ? shortcutAttributes : disabledAttributes];
    }

    [editorColor(75, 90, 111, 0.58) setStroke];
    NSInteger separatorIndexes[] = {2, 5};
    for (NSInteger nextIndex : separatorIndexes) {
        CGFloat separatorY = NSMinY(_contextMenuFrame) + [self contextMenuRowOffset:nextIndex] -
                             kContextMenuSeparatorHeight * 0.5;
        NSBezierPath* separator = [NSBezierPath bezierPath];
        separator.lineWidth = 1.0;
        [separator moveToPoint:NSMakePoint(NSMinX(_contextMenuFrame) + 12.0, separatorY)];
        [separator lineToPoint:NSMakePoint(NSMaxX(_contextMenuFrame) - 12.0, separatorY)];
        [separator stroke];
    }
}

- (void)closeCompletions {
    [_completionPollTimer invalidate];
    _completionPollTimer = nil;
    _completionItems = @[];
    _completionSelectedIndex = 0;
    self.needsDisplay = YES;
}

- (void)refreshCompletionsWithMinimum:(NSUInteger)minimum {
    if (!_autocompleteEnabled || _settingsVisible || _pluginsVisible ||
        [self selectionRange].length > 0) {
        [self closeCompletions];
        return;
    }
    NSData* bytes = [_text dataUsingEncoding:NSUTF8StringEncoding];
    if (bytes == nil || bytes.length > 16 * 1024 * 1024) {
        [self closeCompletions];
        return;
    }
    KineticCompletionItem words[32] = {};
    uint64_t prefixStart = _caretIndex;
    uint32_t count =
        kineticCompletionCollect((const uint8_t*)bytes.bytes, bytes.length, _caretIndex,
                                 (uint32_t)minimum, words, 32, &prefixStart);
    if (prefixStart > _caretIndex || _caretIndex > _text.length) {
        [self closeCompletions];
        return;
    }
    NSString* prefix =
        [_text substringWithRange:NSMakeRange((NSUInteger)prefixStart,
                                              _caretIndex - (NSUInteger)prefixStart)];
    NSString* fileName = _fileUrl.lastPathComponent ?: _documentTitle;
    BOOL pluginProvider = [self.overlayRenderer hasPluginCompletionProviderForFileName:fileName];
    BOOL memberAccess = prefix.length == 0 && _caretIndex > 0 &&
                        ([_text characterAtIndex:_caretIndex - 1] == '.' ||
                         (_caretIndex > 1 && (([_text characterAtIndex:_caretIndex - 2] == '-' &&
                                               [_text characterAtIndex:_caretIndex - 1] == '>') ||
                                              ([_text characterAtIndex:_caretIndex - 2] == ':' &&
                                               [_text characterAtIndex:_caretIndex - 1] == ':'))));
    if (prefix.length < minimum && !(pluginProvider && memberAccess)) {
        [self closeCompletions];
        return;
    }
    NSMutableArray<NSDictionary<NSString*, NSString*>*>* result = [NSMutableArray array];
    NSMutableSet<NSString*>* seen = [NSMutableSet set];
    NSArray* provided = [self.overlayRenderer pluginCompletionItemsForPrefix:prefix
                                                                    fileName:fileName];
    for (NSDictionary<NSString*, NSString*>* item in provided) {
        NSString* insertText = item[@"insertText"];
        if (insertText.length == 0 || insertText.length > 95 ||
            [insertText isEqualToString:prefix] || [seen containsObject:insertText]) {
            continue;
        }
        [seen addObject:insertText];
        [result addObject:item];
    }
    if (!pluginProvider) {
        for (uint32_t index = 0; index < count; ++index) {
            NSString* label = [NSString stringWithUTF8String:(const char*)words[index].label];
            if (label.length == 0 || [seen containsObject:label]) {
                continue;
            }
            [seen addObject:label];
            [result addObject:@{@"label" : label, @"insertText" : label, @"detail" : @"Word"}];
        }
    }
    if (pluginProvider && provided.count == 0 && _completionPollTimer == nil) {
        _completionPollCount = 0;
        _completionPollTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                                target:self
                                                              selector:@selector(pollCompletions:)
                                                              userInfo:nil
                                                               repeats:YES];
    } else if (provided.count > 0 && _completionPollTimer != nil) {
        [_completionPollTimer invalidate];
        _completionPollTimer = nil;
    }
    _completionPrefixStart = (NSUInteger)prefixStart;
    _completionItems =
        [result subarrayWithRange:NSMakeRange(0, MIN(result.count, _autocompleteMaxResults))];
    _completionSelectedIndex = 0;
    self.needsDisplay = YES;
}

- (void)pollCompletions:(NSTimer*)timer {
    (void)timer;
    if (++_completionPollCount > 20 || !_autocompleteEnabled || _settingsVisible ||
        _pluginsVisible) {
        [_completionPollTimer invalidate];
        _completionPollTimer = nil;
        return;
    }
    [self refreshCompletionsWithMinimum:_autocompleteMinPrefix];
}

- (NSRect)completionPopupRect {
    if (_completionItems.count == 0) {
        return NSZeroRect;
    }
    NSString* beforeCaret = [_text substringToIndex:_caretIndex];
    NSArray<NSString*>* lines = [beforeCaret componentsSeparatedByString:@"\n"];
    NSString* line = lines.lastObject ?: @"";
    CGFloat textX = [self editorTextOriginX];
    CGFloat caretX =
        textX - _horizontalScroll + [line sizeWithAttributes:[self editorTextAttributes]].width;
    CGFloat caretY = kFirstLineY + (lines.count - 1) * _lineHeight - _verticalScroll;
    CGFloat height = 8.0 + _completionItems.count * 26.0;
    CGFloat contentWidth = 0.0;
    NSDictionary* labelFont = @{NSFontAttributeName : [NSFont systemFontOfSize:13.0]};
    NSDictionary* detailFont = @{NSFontAttributeName : [NSFont systemFontOfSize:11.0]};
    for (NSDictionary* item in _completionItems) {
        NSString* detail = item[@"detail"];
        CGFloat detailWidth = detail.length > 0 && ![detail isEqualToString:@"Word"]
                                  ? [detail sizeWithAttributes:detailFont].width + 18.0
                                  : 0.0;
        contentWidth =
            MAX(contentWidth, [item[@"label"] sizeWithAttributes:labelFont].width + detailWidth);
    }
    CGFloat width =
        MIN(MAX(130.0, contentWidth + 26.0), MIN(300.0, NSWidth(self.bounds) - textX - 12.0));
    CGFloat x = MIN(MAX(textX, caretX), NSWidth(self.bounds) - width - 10.0);
    CGFloat y = caretY + _lineHeight + 3.0;
    if (y + height > NSHeight(self.bounds) - 8.0) {
        y = MAX(kFirstLineY, caretY - height - 3.0);
    }
    return NSMakeRect(x, y, width, height);
}

- (void)drawCompletions {
    NSRect popup = [self completionPopupRect];
    if (NSIsEmptyRect(popup)) {
        return;
    }
    [editorColor(35, 44, 58, 0.98) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:popup xRadius:6.0 yRadius:6.0] fill];
    [editorColor(87, 108, 139, 0.8) setStroke];
    [[NSBezierPath bezierPathWithRoundedRect:popup xRadius:6.0 yRadius:6.0] stroke];
    for (NSUInteger index = 0; index < _completionItems.count; ++index) {
        CGFloat y = NSMinY(popup) + 4.0 + index * 26.0;
        if ((NSInteger)index == _completionSelectedIndex) {
            [editorColor(61, 83, 120, 0.9) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX(popup) + 4.0, y,
                                                                NSWidth(popup) - 8.0, 25.0)
                                             xRadius:3.0
                                             yRadius:3.0] fill];
        }
        NSDictionary* item = _completionItems[index];
        NSString* detail = item[@"detail"];
        BOOL showDetail = detail.length > 0 && ![detail isEqualToString:@"Word"];
        CGFloat detailWidth =
            showDetail ? MIN(90.0, [detail sizeWithAttributes:@{
                                       NSFontAttributeName : [NSFont systemFontOfSize:11.0]
                                   }]
                                           .width +
                                       8.0)
                       : 0.0;
        [item[@"label"] drawInRect:NSMakeRect(NSMinX(popup) + 11.0, y + 3.0,
                                              NSWidth(popup) - detailWidth - 20.0, 20.0)
                    withAttributes:@{
                        NSFontAttributeName : [NSFont systemFontOfSize:13.0],
                        NSForegroundColorAttributeName : editorColor(226, 235, 248),
                    }];
        if (showDetail) {
            [detail drawInRect:NSMakeRect(NSMaxX(popup) - detailWidth - 8.0, y + 4.0, detailWidth,
                                          18.0)
                withAttributes:@{
                    NSFontAttributeName : [NSFont systemFontOfSize:11.0],
                    NSForegroundColorAttributeName : editorColor(145, 162, 184),
                }];
        }
    }
}

- (void)acceptCompletionAtIndex:(NSUInteger)index {
    if (index >= _completionItems.count || _completionPrefixStart > _caretIndex) {
        return;
    }
    NSString* insertion = _completionItems[index][@"insertText"];
    NSRange range = NSMakeRange(_completionPrefixStart, _caretIndex - _completionPrefixStart);
    [self recordUndoState];
    if (![self replaceTextInRange:range withString:insertion]) {
        return;
    }
    _caretIndex = range.location + insertion.length;
    _selectionAnchor = _caretIndex;
    [self updateDirtyState];
    [self closeCompletions];
    [self ensureCaretVisible];
}

- (void)drawCaretAtRect:(NSRect)target {
    NSPoint destinations[4] = {
        NSMakePoint(NSMinX(target), NSMinY(target)),
        NSMakePoint(NSMaxX(target), NSMinY(target)),
        NSMakePoint(NSMaxX(target), NSMaxY(target)),
        NSMakePoint(NSMinX(target), NSMaxY(target)),
    };
    BOOL animate = _smoothCaret && _motionEnabled && !_draggingSelection &&
                   !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (!_caretPositionValid || !animate) {
        for (NSUInteger i = 0; i < 4; ++i) {
            _caretCorners[i] = destinations[i];
        }
        _caretTarget = target;
        _caretPositionValid = YES;
        [_caretTimer invalidate];
        _caretTimer = nil;
    } else if (!NSEqualRects(target, _caretTarget)) {
        for (NSUInteger i = 0; i < 4; ++i) {
            _caretStarts[i] = _caretCorners[i];
        }
        _caretTarget = target;
        _caretStartTime = now;
        if (_caretTimer == nil) {
            __weak KineticEditorView* weakSelf = self;
            _caretTimer = [NSTimer timerWithTimeInterval:1.0 / 120.0
                                                 repeats:YES
                                                   block:^(NSTimer* timer) {
                                                     KineticEditorView* view = weakSelf;
                                                     if (view == nil || view.window == nil ||
                                                         NSProcessInfo.processInfo.systemUptime -
                                                                 view->_caretStartTime >=
                                                             view->_caretDuration / 1000.0) {
                                                         [timer invalidate];
                                                         if (view != nil) {
                                                             view->_caretTimer = nil;
                                                         }
                                                     }
                                                     view.needsDisplay = YES;
                                                   }];
            [NSRunLoop.mainRunLoop addTimer:_caretTimer forMode:NSRunLoopCommonModes];
        }
    }
    if (animate && _caretTimer != nil) {
        CGFloat progress = MIN(1.0, (now - _caretStartTime) / (_caretDuration / 1000.0));
        NSPoint center = NSMakePoint(0, 0);
        for (NSUInteger i = 0; i < 4; ++i) {
            center.x += _caretStarts[i].x / 4;
            center.y += _caretStarts[i].y / 4;
        }
        CGFloat dx = NSMidX(target) - center.x;
        CGFloat dy = NSMidY(target) - center.y;
        for (NSUInteger i = 0; i < 4; ++i) {
            CGFloat facing = (destinations[i].x - NSMidX(target)) * dx +
                             (destinations[i].y - NSMidY(target)) * dy;
            CGFloat speed = facing > 0 ? 1 + _caretStretch * 2 : 1;
            CGFloat inverse = 1 - MIN(1.0, progress * speed);
            CGFloat eased = 1 - inverse * inverse * inverse;
            _caretCorners[i] =
                NSMakePoint(_caretStarts[i].x + (destinations[i].x - _caretStarts[i].x) * eased,
                            _caretStarts[i].y + (destinations[i].y - _caretStarts[i].y) * eased);
        }
    } else {
        for (NSUInteger i = 0; i < 4; ++i) {
            _caretCorners[i] = destinations[i];
        }
    }
    NSBezierPath* shape = [NSBezierPath bezierPath];
    [shape moveToPoint:_caretCorners[0]];
    for (NSUInteger i = 1; i < 4; ++i) {
        [shape lineToPoint:_caretCorners[i]];
    }
    [shape closePath];
    [shape fill];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [(_canvasColor ?: editorColor(47, 57, 71, 0.9)) setFill];
    NSRectFill(self.bounds);

    if ([self visibleTabCount] > 0) {
        [editorColor(42, 51, 64, 0.9) setFill];
        NSRectFill(NSMakeRect(0.0, kTabBarY, NSWidth(self.bounds), kTabBarHeight));
    }

    NSDictionary* tabAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName : editorColor(220, 228, 239),
    };
    NSMutableParagraphStyle* tabStyle = [[NSMutableParagraphStyle alloc] init];
    tabStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    NSMutableDictionary* truncatingTabAttributes = [tabAttributes mutableCopy];
    truncatingTabAttributes[NSParagraphStyleAttributeName] = tabStyle;

    NSUInteger tabCount = [self visibleTabCount];
    for (NSUInteger index = 0; index < tabCount; ++index) {
        BOOL active = index == _activeTabIndex;
        NSRect tabRect = [self tabRectAtIndex:index];
        if (active) {
            [editorColor(47, 57, 71, 0.94) setFill];
            NSRectFill(tabRect);
            [editorColor(77, 141, 255) setFill];
            NSRectFill(NSMakeRect(NSMinX(tabRect), NSMaxY(tabRect) - 2.0, NSWidth(tabRect), 2.0));
        } else if (_hoveredTabIndex == (NSInteger)index) {
            [editorColor(58, 69, 84, 0.62) setFill];
            NSRectFill(tabRect);
        }
        if (index > 0) {
            [editorColor(71, 84, 103, 0.34) setFill];
            NSRectFill(
                NSMakeRect(NSMinX(tabRect), NSMinY(tabRect) + 7.0, 1.0, NSHeight(tabRect) - 14.0));
        }

        NSString* tabTitle = _tabTitles[index];
        [tabTitle drawInRect:NSMakeRect(NSMinX(tabRect) + 12.0, NSMinY(tabRect) + 9.0,
                                        NSWidth(tabRect) - 43.0, 18.0)
              withAttributes:truncatingTabAttributes];

        NSRect closeRect = [self closeRectAtIndex:index];
        BOOL closeHovered = _hoveredTabCloseIndex == (NSInteger)index;
        if (closeHovered) {
            [editorColor(77, 141, 255, 0.18) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:closeRect xRadius:3.0 yRadius:3.0] fill];
        }
        BOOL dirty = index == _activeTabIndex ? _dirty : [_dirtyTabIndexes containsIndex:index];
        if (dirty && !closeHovered) {
            [editorColor(255, 145, 92) setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMidX(closeRect) - 3.0,
                                                               NSMidY(closeRect) - 3.0, 6.0, 6.0)]
                fill];
        } else {
            NSBezierPath* closeIcon = [NSBezierPath bezierPath];
            closeIcon.lineWidth = 1.15;
            closeIcon.lineCapStyle = NSLineCapStyleRound;
            [closeIcon moveToPoint:NSMakePoint(NSMidX(closeRect) - 3.0, NSMidY(closeRect) - 3.0)];
            [closeIcon lineToPoint:NSMakePoint(NSMidX(closeRect) + 3.0, NSMidY(closeRect) + 3.0)];
            [closeIcon moveToPoint:NSMakePoint(NSMidX(closeRect) + 3.0, NSMidY(closeRect) - 3.0)];
            [closeIcon lineToPoint:NSMakePoint(NSMidX(closeRect) - 3.0, NSMidY(closeRect) + 3.0)];
            [editorColor(171, 184, 201) setStroke];
            [closeIcon stroke];
        }
    }

    if (_workspacePlaceholder) {
        NSString* title = @"No file open";
        NSString* detail = @"Choose a file in Explorer or create a new text file.";
        NSDictionary* titleStyle = @{
            NSFontAttributeName : [NSFont systemFontOfSize:17.0 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName : editorColor(180, 194, 214),
        };
        NSDictionary* detailStyle = @{
            NSFontAttributeName : [NSFont systemFontOfSize:12.0],
            NSForegroundColorAttributeName : editorColor(125, 140, 161),
        };
        CGFloat centerX = [self editorContentX] + [self editorViewportWidth] * 0.5;
        [title drawAtPoint:NSMakePoint(centerX - [title sizeWithAttributes:titleStyle].width * 0.5,
                                       NSHeight(self.bounds) * 0.46)
            withAttributes:titleStyle];
        [detail drawAtPoint:NSMakePoint(centerX -
                                            [detail sizeWithAttributes:detailStyle].width * 0.5,
                                        NSHeight(self.bounds) * 0.46 + 31.0)
             withAttributes:detailStyle];
        return;
    }

    [self clampScroll];
    NSDictionary* textAttributes = [self editorTextAttributes];
    NSDictionary* lineNumberAttributes = @{
        NSFontAttributeName : [NSFont monospacedDigitSystemFontOfSize:12.0
                                                               weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : editorColor(118, 132, 151),
    };

    NSArray<NSString*>* lines = [self documentLines];
    NSArray<NSArray<NSDictionary<NSString*, id>*>*>* syntaxTokens =
        [self syntaxTokensForLines:lines];
    NSMutableDictionary<NSNumber*, NSMutableArray<NSDictionary<NSString*, id>*>*>*
        diagnosticsByLine = [NSMutableDictionary dictionary];
    for (NSDictionary<NSString*, id>* diagnostic in (_showDiagnostics ? _diagnostics : @[])) {
        NSNumber* line = diagnostic[@"line"];
        if (diagnosticsByLine[line] == nil) {
            diagnosticsByLine[line] = [NSMutableArray array];
        }
        [diagnosticsByLine[line] addObject:diagnostic];
    }
    CGFloat contentX = [self editorContentX];
    CGFloat textOriginX = [self editorTextOriginX];
    NSRect contentRect =
        NSMakeRect(contentX, 68.0, NSWidth(self.bounds) - contentX, NSHeight(self.bounds) - 68.0);
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:contentRect] addClip];
    NSUInteger lineStart = 0;
    for (NSUInteger index = 0; index < lines.count; ++index) {
        NSString* line = lines[index];
        NSUInteger currentLineStart = lineStart;
        if (_showCurrentLine && _caretIndex >= lineStart &&
            _caretIndex <= lineStart + line.length) {
            [editorColor(61, 83, 120, 0.22) setFill];
            NSRectFillUsingOperation(NSMakeRect(contentX,
                                                kFirstLineY + index * _lineHeight - _verticalScroll,
                                                NSWidth(contentRect), _lineHeight),
                                     NSCompositingOperationSourceOver);
        }
        lineStart += line.length + (index + 1 < lines.count ? 1 : 0);
        CGFloat y = kFirstLineY + index * _lineHeight - _verticalScroll;
        if (y + _lineHeight < NSMinY(contentRect) || y > NSMaxY(contentRect)) {
            continue;
        }
        if (_showLineNumbers) {
            NSString* lineNumber = [NSString stringWithFormat:@"%lu", (unsigned long)(index + 1)];
            NSSize numberSize = [lineNumber sizeWithAttributes:lineNumberAttributes];
            [lineNumber drawAtPoint:NSMakePoint(textOriginX - 16.0 - numberSize.width, y)
                     withAttributes:lineNumberAttributes];
        }
        if (_searchOpen && _searchPopover.scope == KineticSearchScopeFile) {
            for (NSDictionary* result in _searchPopover.results) {
                NSUInteger resultLine = [result[@"line"] unsignedIntegerValue];
                if (resultLine < index + 1) {
                    continue;
                }
                if (resultLine > index + 1) {
                    break;
                }
                NSUInteger column = [result[@"column"] unsignedIntegerValue] - 1;
                NSUInteger length = [result[@"length"] unsignedIntegerValue];
                if (column >= line.length) {
                    continue;
                }
                length = MIN(length, line.length - column);
                CGFloat beforeWidth =
                    [[line substringToIndex:column] sizeWithAttributes:textAttributes].width;
                CGFloat matchWidth = [[line substringWithRange:NSMakeRange(column, length)]
                                         sizeWithAttributes:textAttributes]
                                         .width;
                [editorColor(255, 145, 92, 0.21) setFill];
                NSRectFill(NSMakeRect(floor(textOriginX - _horizontalScroll + beforeWidth), y,
                                      MAX(2.0, matchWidth), _lineHeight));
            }
        }
        NSRange selection = [self selectionRange];
        NSUInteger lineEnd = currentLineStart + line.length;
        NSUInteger selectionStart = selection.location;
        NSUInteger selectionEnd = NSMaxRange(selection);
        NSUInteger segmentStart = MAX(selectionStart, currentLineStart);
        NSUInteger segmentEnd = MIN(selectionEnd, lineEnd);
        BOOL selectsNewline =
            index + 1 < lines.count && selectionStart <= lineEnd && selectionEnd > lineEnd;
        if (segmentEnd > segmentStart || selectsNewline) {
            NSString* beforeSelection =
                [line substringToIndex:MIN(segmentStart - currentLineStart, line.length)];
            NSString* selectedText =
                [line substringWithRange:NSMakeRange(segmentStart - currentLineStart,
                                                     segmentEnd - segmentStart)];
            CGFloat selectionX = textOriginX - _horizontalScroll +
                                 [beforeSelection sizeWithAttributes:textAttributes].width;
            CGFloat selectionWidth = [selectedText sizeWithAttributes:textAttributes].width;
            if (selectsNewline) {
                selectionWidth += 7.8;
            }
            [editorColor(77, 141, 255, 0.34) setFill];
            NSRectFill(NSMakeRect(floor(selectionX), y, MAX(1.5, selectionWidth), _lineHeight));
        }
        if (index < syntaxTokens.count && syntaxTokens[index].count > 0) {
            NSMutableAttributedString* highlightedLine =
                [[NSMutableAttributedString alloc] initWithString:line attributes:textAttributes];
            for (NSDictionary<NSString*, id>* token in syntaxTokens[index]) {
                NSRange range = [token[@"range"] rangeValue];
                if (NSMaxRange(range) <= line.length) {
                    [highlightedLine
                        addAttribute:NSForegroundColorAttributeName
                               value:syntaxColor((KineticSyntaxKind)[token[@"kind"] integerValue])
                               range:range];
                }
            }
            [highlightedLine drawAtPoint:NSMakePoint(textOriginX - _horizontalScroll, y)];
        } else {
            [line drawAtPoint:NSMakePoint(textOriginX - _horizontalScroll, y)
                withAttributes:textAttributes];
        }
        if (_showIndentGuides) {
            NSUInteger column = 0;
            NSDictionary* markerStyle = @{
                NSFontAttributeName : [NSFont monospacedSystemFontOfSize:10.0
                                                                  weight:NSFontWeightRegular],
                NSForegroundColorAttributeName : editorColor(137, 157, 185, 0.48),
            };
            for (NSUInteger offset = 0; offset < MIN(line.length, (NSUInteger)256); ++offset) {
                unichar character = [line characterAtIndex:offset];
                if (character != ' ' && character != '\t') {
                    break;
                }
                CGFloat markerX =
                    textOriginX - _horizontalScroll +
                    [[line substringToIndex:offset] sizeWithAttributes:textAttributes].width;
                [character == '\t' ? @"→" : @"·" drawAtPoint:NSMakePoint(markerX + 2.0, y + 2.0)
                                              withAttributes:markerStyle];
                column += character == '\t' ? _tabWidth - column % _tabWidth : 1;
                if (column % _tabWidth == 0) {
                    CGFloat guideX =
                        textOriginX - _horizontalScroll +
                        [[line substringToIndex:offset + 1] sizeWithAttributes:textAttributes]
                            .width -
                        3.0;
                    [editorColor(106, 128, 158, 0.24) setStroke];
                    NSBezierPath* guide = [NSBezierPath bezierPath];
                    [guide moveToPoint:NSMakePoint(guideX, y)];
                    [guide lineToPoint:NSMakePoint(guideX, y + _lineHeight)];
                    [guide stroke];
                }
            }
        }
        NSArray<NSDictionary<NSString*, id>*>* lineDiagnostics = diagnosticsByLine[@(index + 1)];
        for (NSDictionary<NSString*, id>* diagnostic in lineDiagnostics) {
            NSUInteger column = MIN([diagnostic[@"column"] unsignedIntegerValue], line.length);
            NSUInteger length =
                MIN(MAX(1, [diagnostic[@"length"] unsignedIntegerValue]), line.length - column);
            CGFloat startX =
                textOriginX - _horizontalScroll +
                [[line substringToIndex:column] sizeWithAttributes:textAttributes].width;
            CGFloat width = length == 0 ? 7.0
                                        : [[line substringWithRange:NSMakeRange(column, length)]
                                              sizeWithAttributes:textAttributes]
                                              .width;
            NSColor* diagnosticColor = [diagnostic[@"severity"] unsignedIntegerValue] == 1
                                           ? editorColor(255, 113, 119)
                                           : editorColor(246, 184, 95);
            [diagnosticColor setStroke];
            NSBezierPath* underline = [NSBezierPath bezierPath];
            underline.lineWidth = 1.1;
            CGFloat underlineY = y + _lineHeight - 2.0;
            for (CGFloat offset = 0.0; offset <= MAX(7.0, width); offset += 4.0) {
                NSPoint point = NSMakePoint(
                    startX + offset, underlineY + ((int)(offset / 4.0) % 2 == 0 ? 0.0 : 2.0));
                if (offset == 0.0) {
                    [underline moveToPoint:point];
                } else {
                    [underline lineToPoint:point];
                }
            }
            [underline stroke];
        }
    }

    NSString* beforeCaret = [_text substringToIndex:_caretIndex];
    NSArray<NSString*>* caretLines = [beforeCaret componentsSeparatedByString:@"\n"];
    NSString* caretLine = caretLines.lastObject ?: @"";
    CGFloat caretX =
        textOriginX - _horizontalScroll + [caretLine sizeWithAttributes:textAttributes].width;
    CGFloat caretY = kFirstLineY + (caretLines.count - 1) * _lineHeight - _verticalScroll;
    [editorColor(111, 166, 255) setFill];
    [self drawCaretAtRect:NSMakeRect(floor(caretX), caretY + 1.0, 1.5, _fontSize + 3.0)];
    [self.overlayRenderer drawPluginOverlaysInRect:contentRect];
    [NSGraphicsContext restoreGraphicsState];

    if (_hoveredDiagnosticIndex < _diagnostics.count) {
        NSDictionary<NSString*, id>* diagnostic = _diagnostics[_hoveredDiagnosticIndex];
        NSUInteger lineIndex = [diagnostic[@"line"] unsignedIntegerValue] - 1;
        NSRect popover = [self diagnosticPopoverRectForLine:lineIndex];
        if (!NSIsEmptyRect(popover) && NSMaxY(popover) > 68.0) {
            [editorColor(35, 44, 58, 0.98) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:popover xRadius:6.0 yRadius:6.0] fill];
            [editorColor(87, 108, 139, 0.8) setStroke];
            [[NSBezierPath bezierPathWithRoundedRect:popover xRadius:6.0 yRadius:6.0] stroke];
            NSRect fixRect = [self fixRectForLine:lineIndex diagnostic:diagnostic];
            CGFloat textRight =
                NSIsEmptyRect(fixRect) ? NSMaxX(popover) - 12.0 : NSMinX(fixRect) - 8.0;
            [diagnostic[@"message"]
                    drawInRect:NSMakeRect(NSMinX(popover) + 12.0, NSMinY(popover) + 7.0,
                                          textRight - NSMinX(popover) - 12.0, 36.0)
                withAttributes:@{
                    NSFontAttributeName : [NSFont systemFontOfSize:11.5],
                    NSForegroundColorAttributeName :
                                [diagnostic[@"severity"] unsignedIntegerValue] == 1
                        ? editorColor(255, 149, 154)
                        : editorColor(246, 194, 116),
                }];
            if (!NSIsEmptyRect(fixRect)) {
                [editorColor(68, 106, 164, 0.72) setFill];
                [[NSBezierPath bezierPathWithRoundedRect:fixRect xRadius:4.0 yRadius:4.0] fill];
                [@"Fix" drawInRect:NSInsetRect(fixRect, 6.0, 3.0)
                    withAttributes:@{
                        NSFontAttributeName : [NSFont systemFontOfSize:10.0
                                                                weight:NSFontWeightMedium],
                        NSForegroundColorAttributeName : editorColor(226, 237, 252),
                    }];
            }
        }
    }

    CGFloat maximumVertical = [self maximumVerticalScroll];
    if (_showScrollIndicators && maximumVertical > 0.0) {
        NSRect track = NSMakeRect(NSWidth(self.bounds) - 7.0, 74.0, 3.0,
                                  MAX(20.0, NSHeight(self.bounds) - 82.0));
        CGFloat contentHeight = lines.count * _lineHeight;
        CGFloat thumbHeight = MAX(28.0, NSHeight(track) * NSHeight(track) / contentHeight);
        CGFloat thumbY =
            NSMinY(track) + (NSHeight(track) - thumbHeight) * (_verticalScroll / maximumVertical);
        [editorColor(139, 155, 177, 0.38) setFill];
        [[NSBezierPath
            bezierPathWithRoundedRect:NSMakeRect(NSMinX(track), thumbY, NSWidth(track), thumbHeight)
                              xRadius:1.5
                              yRadius:1.5] fill];
    }

    CGFloat maximumHorizontal = [self maximumHorizontalScroll];
    if (_showScrollIndicators && maximumHorizontal > 0.0) {
        NSRect track = NSMakeRect(textOriginX, NSHeight(self.bounds) - 6.0,
                                  MAX(20.0, NSWidth(self.bounds) - textOriginX - 12.0), 3.0);
        CGFloat thumbWidth =
            MAX(32.0, NSWidth(track) * NSWidth(track) / (NSWidth(track) + maximumHorizontal));
        CGFloat thumbX =
            NSMinX(track) + (NSWidth(track) - thumbWidth) * (_horizontalScroll / maximumHorizontal);
        [editorColor(139, 155, 177, 0.38) setFill];
        [[NSBezierPath
            bezierPathWithRoundedRect:NSMakeRect(thumbX, NSMinY(track), thumbWidth, NSHeight(track))
                              xRadius:1.5
                              yRadius:1.5] fill];
    }

    [self drawCompletions];
    [self drawContextMenu];
}

- (void)mouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect completionPopup = [self completionPopupRect];
    if (!NSIsEmptyRect(completionPopup) && NSPointInRect(point, completionPopup)) {
        NSInteger index = (NSInteger)floor((point.y - NSMinY(completionPopup) - 4.0) / 26.0);
        if (index >= 0 && index < (NSInteger)_completionItems.count) {
            [self acceptCompletionAtIndex:(NSUInteger)index];
        }
        return;
    }
    [self closeCompletions];
    if (_searchOpen) {
        [self closeSearch];
    }
    if (_contextMenuVisible) {
        NSInteger menuIndex = [self contextMenuIndexAtPoint:point];
        [self hideContextMenu];
        if (menuIndex >= 0) {
            [self performContextMenuItem:menuIndex];
            return;
        }
    }
    if (point.y >= kTabBarY && point.y < kTabBarY + kTabBarHeight) {
        for (NSUInteger index = 0; index < [self visibleTabCount]; ++index) {
            if (NSPointInRect(point, [self closeRectAtIndex:index])) {
                [self.commandHandler closeTabAtIndex:index];
                return;
            }
            if (NSPointInRect(point, [self tabRectAtIndex:index])) {
                if (index < _tabTitles.count) {
                    if (_settingsVisible || _pluginsVisible)
                        [self closeUtilityPanel];
                    [self.commandHandler activateTabAtIndex:index];
                }
                return;
            }
        }
    }
    [self.window makeFirstResponder:self];
    if (_settingsVisible || _pluginsVisible)
        return;
    if (_workspacePlaceholder) {
        return;
    }
    if (point.y < 68.0) {
        return;
    }

    if (_hoveredDiagnosticIndex < _diagnostics.count) {
        NSDictionary<NSString*, id>* diagnostic = _diagnostics[_hoveredDiagnosticIndex];
        NSUInteger hoveredLine = [diagnostic[@"line"] unsignedIntegerValue] - 1;
        if (NSPointInRect(point, [self fixRectForLine:hoveredLine diagnostic:diagnostic])) {
            [self.overlayRenderer
                applyPluginDiagnosticFixForPath:self.fileUrl.path
                                           line:hoveredLine + 1
                                         column:[diagnostic[@"column"] unsignedIntegerValue]
                                         length:[diagnostic[@"length"] unsignedIntegerValue]];
            return;
        }
    }

    NSUInteger index = [self textIndexForPoint:point];
    if (_indentUnitNavigation) {
        index = kineticIndentSnapIndex(_text, index, _tabWidth);
    }
    if ((event.modifierFlags & NSEventModifierFlagShift) == 0) {
        _selectionAnchor = index;
    }
    _caretIndex = index;
    _draggingSelection = YES;
    [self ensureCaretVisible];
    self.needsDisplay = YES;
}

- (void)rightMouseDown:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (point.y >= kTabBarY && point.y < kTabBarY + kTabBarHeight) {
        for (NSUInteger index = 0; index < [self visibleTabCount]; ++index) {
            if (!NSPointInRect(point, [self tabRectAtIndex:index])) {
                continue;
            }
            [KineticContextMenu showInView:self
                                   atPoint:point
                                     items:@[ @{@"title" : @"Close Tab", @"shortcut" : @"⌘W"} ]
                                   handler:^(NSUInteger selected) {
                                     (void)selected;
                                     [self.commandHandler closeTabAtIndex:index];
                                   }];
            return;
        }
    }
    if (_settingsVisible || _pluginsVisible) {
        return;
    }
    if (point.y < 68.0) {
        [self hideContextMenu];
        return;
    }

    [self.window makeFirstResponder:self];
    NSUInteger index = [self textIndexForPoint:point];
    NSRange selection = [self selectionRange];
    BOOL clickedSelection =
        selection.length > 0 && index >= selection.location && index <= NSMaxRange(selection);
    if (!clickedSelection) {
        _caretIndex = index;
        _selectionAnchor = index;
    }
    [self showContextMenuAtPoint:point];
}

- (void)mouseDragged:(NSEvent*)event {
    if (!_draggingSelection) {
        return;
    }

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (point.y < kFirstLineY) {
        _verticalScroll -= _lineHeight;
    } else if (point.y > NSHeight(self.bounds) - 8.0) {
        _verticalScroll += _lineHeight;
    }
    if (point.x < [self editorTextOriginX]) {
        _horizontalScroll -= 12.0;
    } else if (point.x > NSWidth(self.bounds) - 8.0) {
        _horizontalScroll += 12.0;
    }
    [self clampScroll];
    _caretIndex = [self textIndexForPoint:point];
    [self ensureCaretVisible];
    self.needsDisplay = YES;
}

- (void)mouseUp:(NSEvent*)event {
    (void)event;
    _draggingSelection = NO;
}

- (void)resetCursorRects {
    [super resetCursorRects];
    if (_workspacePlaceholder && !_settingsVisible && !_pluginsVisible) {
        CGFloat top = [self workspaceContentY];
        [self addCursorRect:NSMakeRect([self editorContentX], top,
                                       NSWidth(self.bounds) - [self editorContentX],
                                       MAX(0.0, NSHeight(self.bounds) - top))
                     cursor:NSCursor.arrowCursor];
        return;
    }
    if (_settingsVisible || _pluginsVisible) {
        [self addCursorRect:NSMakeRect(KineticActivityBar.railWidth, 68.0,
                                       NSWidth(self.bounds) - KineticActivityBar.railWidth,
                                       MAX(0.0, NSHeight(self.bounds) - 68.0))
                     cursor:NSCursor.arrowCursor];
        return;
    }
    CGFloat contentX = [self editorContentX];
    NSRect editorRect = NSMakeRect(contentX, 68.0, NSWidth(self.bounds) - contentX,
                                   MAX(0.0, NSHeight(self.bounds) - 68.0));
    [self addCursorRect:editorRect cursor:NSCursor.IBeamCursor];
    if (_contextMenuVisible) {
        [self addCursorRect:_contextMenuFrame cursor:NSCursor.arrowCursor];
    }
}

- (void)activityBarDidRequestOpenFile:(KineticActivityBar*)activityBar {
    (void)activityBar;
    [self.commandHandler openFile];
}

- (void)activityBarDidRequestOpenFolder:(KineticActivityBar*)activityBar {
    (void)activityBar;
    [self.commandHandler openFolder];
}

- (void)activityBarDidRequestCreateFolder:(KineticActivityBar*)activityBar {
    (void)activityBar;
    [self.commandHandler createFolder];
}

- (void)activityBar:(KineticActivityBar*)activityBar didRequestCreateFileInDirectory:(NSURL*)url {
    (void)activityBar;
    [self.commandHandler createFileInDirectory:url];
}

- (void)activityBar:(KineticActivityBar*)activityBar didRequestCreateFolderInDirectory:(NSURL*)url {
    (void)activityBar;
    [self.commandHandler createFolderInDirectory:url];
}

- (void)activityBarDidRequestSaveFile:(KineticActivityBar*)activityBar {
    (void)activityBar;
    [self.commandHandler saveFile];
}

- (void)activityBarDidRequestCloseTab:(KineticActivityBar*)activityBar {
    (void)activityBar;
    [self.commandHandler closeActiveTab];
}

- (void)activityBar:(KineticActivityBar*)activityBar didRequestPluginCommand:(NSString*)commandId {
    (void)activityBar;
    [self.commandHandler executePluginCommand:commandId];
}

- (void)activityBar:(KineticActivityBar*)activityBar didRequestOpenUrl:(NSURL*)url {
    (void)activityBar;
    [self.commandHandler openFileAtUrl:url];
}

- (void)activityBar:(KineticActivityBar*)activityBar
    didActivateSection:(KineticActivitySection)section {
    (void)activityBar;
    [self setActivitySection:section animated:YES];
    if (section == KineticActivitySectionPlugins)
        [self.commandHandler refreshPluginCatalog];
}

- (void)pluginBrowserDidRequestRefresh:(KineticPluginBrowser*)browser {
    (void)browser;
    [self.commandHandler refreshPluginCatalog];
}

- (void)pluginBrowser:(KineticPluginBrowser*)browser
     didRequestAction:(NSString*)action
            forPlugin:(NSDictionary<NSString*, id>*)plugin {
    (void)browser;
    [self.commandHandler managePlugin:plugin action:action];
}

- (void)searchPopoverDidChange:(KineticSearchPopover*)popover {
    if (popover.scope == KineticSearchScopeFile) {
        [self refreshFileSearch];
    } else {
        [self.commandHandler searchWorkspaceForQuery:popover.query matchCase:popover.matchCase];
    }
}

- (void)searchPopover:(KineticSearchPopover*)popover didSelectResult:(NSDictionary*)result {
    BOOL projectResult = popover.scope == KineticSearchScopeProject;
    [self closeSearch];
    if (projectResult) {
        [self.commandHandler openSearchResult:result];
    } else {
        [self revealLine:[result[@"line"] unsignedIntegerValue]
                  column:[result[@"column"] unsignedIntegerValue]
                  length:[result[@"length"] unsignedIntegerValue]];
    }
}

- (void)searchPopoverDidRequestClose:(KineticSearchPopover*)popover {
    (void)popover;
    [self closeSearch];
}

- (void)updateTrackingAreas {
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                     NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:_trackingArea];
    [super updateTrackingAreas];
}

- (void)mouseMoved:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSUInteger hoveredDiagnostic = NSNotFound;
    if (_showDiagnostics && !_settingsVisible && !_pluginsVisible && !_workspacePlaceholder &&
        point.y >= 68.0) {
        NSArray<NSString*>* lines = [self documentLines];
        NSUInteger lineIndex =
            point.y >= kFirstLineY
                ? (NSUInteger)floor((point.y - kFirstLineY + _verticalScroll) / _lineHeight)
                : NSNotFound;
        if (lineIndex < lines.count) {
            NSString* line = lines[lineIndex];
            NSDictionary* attributes = [self editorTextAttributes];
            for (NSUInteger index = 0; index < _diagnostics.count; ++index) {
                NSDictionary<NSString*, id>* diagnostic = _diagnostics[index];
                if ([diagnostic[@"line"] unsignedIntegerValue] != lineIndex + 1) {
                    continue;
                }
                NSUInteger column = MIN([diagnostic[@"column"] unsignedIntegerValue], line.length);
                NSUInteger length =
                    MIN(MAX(1, [diagnostic[@"length"] unsignedIntegerValue]), line.length - column);
                CGFloat x = [self editorTextOriginX] - _horizontalScroll +
                            [[line substringToIndex:column] sizeWithAttributes:attributes].width;
                CGFloat width = length == 0 ? 7.0
                                            : [[line substringWithRange:NSMakeRange(column, length)]
                                                  sizeWithAttributes:attributes]
                                                  .width;
                if (point.x >= x - 2.0 && point.x <= x + MAX(7.0, width) + 2.0) {
                    hoveredDiagnostic = index;
                    break;
                }
            }
        }
        if (hoveredDiagnostic == NSNotFound && _hoveredDiagnosticIndex < _diagnostics.count) {
            NSDictionary<NSString*, id>* current = _diagnostics[_hoveredDiagnosticIndex];
            NSUInteger currentLine = [current[@"line"] unsignedIntegerValue] - 1;
            CGFloat sourceY = kFirstLineY + currentLine * _lineHeight - _verticalScroll;
            NSRect source = NSMakeRect([self editorContentX], sourceY,
                                       NSWidth(self.bounds) - [self editorContentX], _lineHeight);
            NSRect corridor = NSUnionRect(source, [self diagnosticPopoverRectForLine:currentLine]);
            if (NSPointInRect(point, corridor)) {
                hoveredDiagnostic = _hoveredDiagnosticIndex;
            }
        }
    }
    if (hoveredDiagnostic != _hoveredDiagnosticIndex) {
        _hoveredDiagnosticIndex = hoveredDiagnostic;
        self.needsDisplay = YES;
    }
    NSInteger menuIndex = [self contextMenuIndexAtPoint:point];
    if (menuIndex != _contextMenuHoveredIndex) {
        _contextMenuHoveredIndex = menuIndex;
        self.needsDisplay = YES;
    }
    NSInteger hoveredTab = -1;
    NSInteger hoveredClose = -1;
    for (NSUInteger index = 0; index < [self visibleTabCount]; ++index) {
        if (NSPointInRect(point, [self closeRectAtIndex:index])) {
            hoveredClose = (NSInteger)index;
            hoveredTab = (NSInteger)index;
            break;
        }
        if (NSPointInRect(point, [self tabRectAtIndex:index])) {
            hoveredTab = (NSInteger)index;
            break;
        }
    }
    if (hoveredTab != _hoveredTabIndex || hoveredClose != _hoveredTabCloseIndex) {
        _hoveredTabIndex = hoveredTab;
        _hoveredTabCloseIndex = hoveredClose;
        self.needsDisplay = YES;
    }
}

- (void)mouseExited:(NSEvent*)event {
    (void)event;
    _hoveredTabIndex = -1;
    _hoveredTabCloseIndex = -1;
    _hoveredDiagnosticIndex = NSNotFound;
    self.needsDisplay = YES;
}

- (void)scrollWheel:(NSEvent*)event {
    if (_settingsVisible || _pluginsVisible)
        return;
    [self hideContextMenu];
    BOOL horizontal = fabs(event.scrollingDeltaX) > fabs(event.scrollingDeltaY) ||
                      (event.modifierFlags & NSEventModifierFlagShift) != 0;
    if (horizontal) {
        CGFloat delta =
            fabs(event.scrollingDeltaX) > 0.0 ? event.scrollingDeltaX : event.scrollingDeltaY;
        _horizontalScroll += _naturalScrolling ? -delta : delta;
    } else {
        _verticalScroll += _naturalScrolling ? -event.scrollingDeltaY : event.scrollingDeltaY;
    }
    [self clampScroll];
    self.needsDisplay = YES;
}

- (void)keyDown:(NSEvent*)event {
    if (_settingsVisible || _pluginsVisible) {
        if (event.keyCode == 53)
            [self closeUtilityPanel];
        return;
    }
    if (_workspacePlaceholder) {
        return;
    }
    [self hideContextMenu];
    if ((event.modifierFlags & NSEventModifierFlagControl) != 0 && event.keyCode == 49) {
        [self refreshCompletionsWithMinimum:1];
        return;
    }
    if (_completionItems.count > 0) {
        if (event.keyCode == 53) {
            [self closeCompletions];
            return;
        }
        if (event.keyCode == 125 || event.keyCode == 126) {
            NSInteger direction = event.keyCode == 125 ? 1 : -1;
            _completionSelectedIndex =
                (_completionSelectedIndex + direction + (NSInteger)_completionItems.count) %
                (NSInteger)_completionItems.count;
            self.needsDisplay = YES;
            return;
        }
        if (event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 48) {
            [self acceptCompletionAtIndex:(NSUInteger)_completionSelectedIndex];
            return;
        }
    }
    NSString* beforeEdit = [_text copy];
    BOOL usesCommand = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    BOOL usesOption = (event.modifierFlags & NSEventModifierFlagOption) != 0;
    BOOL extendsSelection = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    NSString* shortcut = event.charactersIgnoringModifiers.lowercaseString;

    if (usesCommand && [shortcut isEqualToString:@"c"]) {
        [self copySelection];
        return;
    }
    if (usesCommand && [shortcut isEqualToString:@"x"]) {
        [self cutSelection];
        [self ensureCaretVisible];
        self.needsDisplay = YES;
        return;
    }
    if (usesCommand && [shortcut isEqualToString:@"v"]) {
        [self pasteText];
        [self refreshCompletionsWithMinimum:_autocompleteMinPrefix];
        [self ensureCaretVisible];
        self.needsDisplay = YES;
        return;
    }
    if (usesCommand && [shortcut isEqualToString:@"a"]) {
        [self selectAllText];
        return;
    }
    if (usesCommand && [shortcut isEqualToString:@"z"]) {
        if (extendsSelection) {
            [self redoEdit];
        } else {
            [self undoEdit];
        }
        return;
    }
    if (usesCommand && [shortcut isEqualToString:@"y"]) {
        [self redoEdit];
        return;
    }

    NSRange initialSelection = [self selectionRange];

    if (event.keyCode == 51) {
        if (initialSelection.length > 0) {
            [self recordUndoState];
            [self deleteSelection];
        } else if (_caretIndex > 0) {
            KineticStructureEdit* pairedEdit =
                !usesCommand && !usesOption
                    ? kineticPairedBackspaceEdit(_text, _caretIndex, _autoPairs)
                    : nil;
            if (pairedEdit != nil) {
                [self applyStructureEdit:pairedEdit];
                [self ensureCaretVisible];
                self.needsDisplay = YES;
                return;
            }
            KineticStructureEdit* indentEdit =
                !usesCommand && !usesOption
                    ? kineticIndentBackspaceEdit(_text, _caretIndex, _tabWidth)
                    : nil;
            if (indentEdit != nil) {
                [self applyStructureEdit:indentEdit];
                [self ensureCaretVisible];
                self.needsDisplay = YES;
                return;
            }
            NSUInteger deletionStart = 0;
            if (usesCommand) {
                deletionStart = [self lineStartIndexFromIndex:_caretIndex];
                if (deletionStart == _caretIndex) {
                    --deletionStart;
                }
            } else if (usesOption) {
                deletionStart = [self previousWordIndexFromIndex:_caretIndex];
            } else {
                deletionStart =
                    [_text rangeOfComposedCharacterSequenceAtIndex:_caretIndex - 1].location;
            }
            [self recordUndoState];
            if (![self replaceTextInRange:NSMakeRange(deletionStart, _caretIndex - deletionStart)
                               withString:@""]) {
                return;
            }
            _caretIndex = deletionStart;
            _selectionAnchor = _caretIndex;
            [self updateDirtyState];
        }
    } else if (event.keyCode == 117) {
        if (initialSelection.length > 0) {
            [self recordUndoState];
            [self deleteSelection];
        } else if (_caretIndex < _text.length) {
            NSUInteger deletionEnd = 0;
            if (usesCommand) {
                deletionEnd = [self lineEndIndexFromIndex:_caretIndex];
                if (deletionEnd == _caretIndex) {
                    ++deletionEnd;
                }
            } else if (usesOption) {
                deletionEnd = [self nextWordIndexFromIndex:_caretIndex];
            } else {
                deletionEnd =
                    NSMaxRange([_text rangeOfComposedCharacterSequenceAtIndex:_caretIndex]);
            }
            [self recordUndoState];
            if (![self replaceTextInRange:NSMakeRange(_caretIndex, deletionEnd - _caretIndex)
                               withString:@""]) {
                return;
            }
            _selectionAnchor = _caretIndex;
            [self updateDirtyState];
        }
    } else if (event.keyCode == 36 || event.keyCode == 76) {
        [self applyStructureEdit:kineticNewlineEditWithTabs(_text, initialSelection,
                                                            _fileUrl.lastPathComponent
                                                                ?: _documentTitle,
                                                            _tabWidth, _autoIndent, _insertTabs)];
    } else if (event.keyCode == 48) {
        [self applyStructureEdit:kineticTabEditWithTabs(_text, initialSelection, _tabWidth,
                                                        extendsSelection, _insertTabs)];
    } else if (event.keyCode == 123) {
        if (!extendsSelection && initialSelection.length > 0) {
            _caretIndex = initialSelection.location;
        } else if (usesCommand) {
            _caretIndex = [self lineStartIndexFromIndex:_caretIndex];
        } else if (usesOption) {
            _caretIndex = [self previousWordIndexFromIndex:_caretIndex];
        } else if (_caretIndex > 0) {
            NSUInteger stop = _indentUnitNavigation
                                  ? kineticIndentNavigationIndex(_text, _caretIndex, _tabWidth, NO)
                                  : NSNotFound;
            _caretIndex =
                stop != NSNotFound
                    ? stop
                    : [_text rangeOfComposedCharacterSequenceAtIndex:_caretIndex - 1].location;
        }
        if (!extendsSelection) {
            _selectionAnchor = _caretIndex;
        }
    } else if (event.keyCode == 124) {
        if (!extendsSelection && initialSelection.length > 0) {
            _caretIndex = NSMaxRange(initialSelection);
        } else if (usesCommand) {
            _caretIndex = [self lineEndIndexFromIndex:_caretIndex];
        } else if (usesOption) {
            _caretIndex = [self nextWordIndexFromIndex:_caretIndex];
        } else if (_caretIndex < _text.length) {
            NSUInteger stop = _indentUnitNavigation
                                  ? kineticIndentNavigationIndex(_text, _caretIndex, _tabWidth, YES)
                                  : NSNotFound;
            _caretIndex =
                stop != NSNotFound
                    ? stop
                    : NSMaxRange([_text rangeOfComposedCharacterSequenceAtIndex:_caretIndex]);
        }
        if (!extendsSelection) {
            _selectionAnchor = _caretIndex;
        }
    } else if (event.keyCode == 126) {
        if (usesCommand) {
            _caretIndex = 0;
        } else {
            [self moveCaretVertically:-1];
        }
        if (!extendsSelection) {
            _selectionAnchor = _caretIndex;
        }
    } else if (event.keyCode == 125) {
        if (usesCommand) {
            _caretIndex = _text.length;
        } else {
            [self moveCaretVertically:1];
        }
        if (!extendsSelection) {
            _selectionAnchor = _caretIndex;
        }
    } else if (event.keyCode == 116) {
        NSInteger pageLines = MAX(1, floor((NSHeight(self.bounds) - kFirstLineY) / _lineHeight));
        [self moveCaretVertically:-pageLines];
        if (!extendsSelection) {
            _selectionAnchor = _caretIndex;
        }
    } else if (event.keyCode == 121) {
        NSInteger pageLines = MAX(1, floor((NSHeight(self.bounds) - kFirstLineY) / _lineHeight));
        [self moveCaretVertically:pageLines];
        if (!extendsSelection) {
            _selectionAnchor = _caretIndex;
        }
    } else {
        if (usesCommand) {
            [super keyDown:event];
            return;
        }
        NSString* characters = event.characters;
        if (characters.length == 0 || [characters characterAtIndex:0] < 0x20) {
            [super keyDown:event];
            return;
        }
        KineticStructureEdit* structureEdit =
            kineticTypedStructureEdit(_text, initialSelection, characters, _tabWidth, _autoPairs);
        if (structureEdit != nil) {
            [self applyStructureEdit:structureEdit];
        } else {
            [self replaceSelectionWithString:characters];
        }
    }

    [self ensureCaretVisible];
    if (![beforeEdit isEqualToString:_text]) {
        [self refreshCompletionsWithMinimum:_autocompleteMinPrefix];
    } else {
        [self closeCompletions];
    }
    self.needsDisplay = YES;
}

@end
