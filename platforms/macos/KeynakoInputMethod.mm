#import <Cocoa/Cocoa.h>
#import <InputMethodKit/InputMethodKit.h>

#include <filesystem>
#include <memory>
#include <string>
#include <utility>

#include "keynako_ime_core.h"
#include "zenzai_client.h"

static IMKServer *gServer;
static IMKCandidates *gCandidates;

static NSString *FromUtf8(const std::string &value) {
    return [[NSString alloc] initWithBytes:value.data()
                                   length:value.size()
                                 encoding:NSUTF8StringEncoding] ?: @"";
}

@interface KeynakoInputController : IMKInputController
@end

@interface KeynakoInputController ()
- (void)selectCandidate:(NSString *)value;
- (void)updateMarkedText:(id)sender;
- (void)commitCurrent:(id)sender;
- (void)cancelComposition:(id)sender;
- (BOOL)addZenzai;
@end

@implementation KeynakoInputController {
    keynako::ImeSession _session;
    std::unique_ptr<keynako::ZenzaiClient> _zenzai;
}

- (BOOL)handleEvent:(NSEvent *)event client:(id)sender {
    if (event.type != NSEventTypeKeyDown) return NO;
    const NSEventModifierFlags modifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    const BOOL control = (modifiers & NSEventModifierFlagControl) != 0;
    const BOOL command = (modifiers & NSEventModifierFlagCommand) != 0;
    const BOOL option = (modifiers & NSEventModifierFlagOption) != 0;

    if (control && event.keyCode == 49) {
        _session.set_mode(_session.mode() == keynako::InputMode::japanese
                              ? keynako::InputMode::english
                              : keynako::InputMode::japanese);
        [self cancelComposition:sender];
        return YES;
    }
    if (command || option || control) return NO;

    const unsigned short key = event.keyCode;
    if (key == 51) {
        if (_session.raw_input().empty()) return NO;
        _session.backspace();
        [self updateMarkedText:sender];
        return YES;
    }
    if (key == 53) {
        if (_session.raw_input().empty()) return NO;
        [self cancelComposition:sender];
        return YES;
    }
    if (key == 36 || key == 76) {
        if (_session.raw_input().empty()) return NO;
        [self commitCurrent:sender];
        return YES;
    }
    if (key == 49 || key == 125) {
        if (_session.raw_input().empty()) return NO;
        const BOOL zenzaiAdded = key == 49 && _session.mode() == keynako::InputMode::japanese && [self addZenzai];
        if (!zenzaiAdded) _session.select_next();
        [self updateMarkedText:sender];
        return YES;
    }
    if (key == 126) {
        if (_session.raw_input().empty()) return NO;
        _session.select_previous();
        [self updateMarkedText:sender];
        return YES;
    }

    NSString *characters = event.charactersIgnoringModifiers.lowercaseString;
    if (characters.length != 1) return NO;
    const unichar scalar = [characters characterAtIndex:0];
    const BOOL accepted = (scalar >= 'a' && scalar <= 'z') || scalar == '-' || scalar == ',' || scalar == '.';
    if (!accepted) return NO;
    _session.append_ascii(static_cast<char>(scalar));
    [self updateMarkedText:sender];
    return YES;
}

- (NSArray *)candidates:(id)sender {
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:_session.candidates().size()];
    for (const auto &candidate : _session.candidates()) [values addObject:FromUtf8(candidate.text)];
    return values;
}

- (void)candidateSelectionChanged:(NSAttributedString *)candidateString {
    [self selectCandidate:candidateString.string];
    id client = [self client];
    if (client) [self updateMarkedText:client];
}

- (void)candidateSelected:(NSAttributedString *)candidateString {
    [self selectCandidate:candidateString.string];
    id client = [self client];
    if (client) [self commitCurrent:client];
}

- (void)commitComposition:(id)sender {
    if (!_session.raw_input().empty()) [self commitCurrent:sender];
}

- (void)deactivateServer:(id)sender {
    if (!_session.raw_input().empty()) [self commitCurrent:sender];
    [super deactivateServer:sender];
}

- (void)selectCandidate:(NSString *)value {
    for (std::size_t index = 0; index < _session.candidates().size(); ++index) {
        if ([FromUtf8(_session.candidates()[index].text) isEqualToString:value]) {
            while (_session.selected_index() != index) _session.select_next();
            break;
        }
    }
}

- (void)updateMarkedText:(id)sender {
    if (_session.raw_input().empty()) {
        [sender setMarkedText:@"" selectionRange:NSMakeRange(0, 0)
             replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
        [gCandidates hide];
        return;
    }
    NSString *text = FromUtf8(_session.display_text());
    [sender setMarkedText:text selectionRange:NSMakeRange(text.length, 0)
         replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
    [gCandidates updateCandidates];
    [gCandidates show:kIMKLocateCandidatesBelowHint];
}

- (void)commitCurrent:(id)sender {
    NSString *text = FromUtf8(_session.selected_text());
    [sender insertText:text replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
    _session.clear();
    [gCandidates hide];
}

- (void)cancelComposition:(id)sender {
    [sender setMarkedText:@"" selectionRange:NSMakeRange(0, 0)
         replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
    _session.clear();
    [gCandidates hide];
}

- (BOOL)addZenzai {
    if (!_zenzai) {
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *helper = [bundle pathForResource:@"keynako_zenzai" ofType:nil];
        NSString *model = [bundle pathForResource:@"ggml-model-Q5_K_M" ofType:@"gguf"
                                      inDirectory:@"zenzai/zenz-v3.2-xsmall-gguf"];
        NSString *configured = NSProcessInfo.processInfo.environment[@"KEYNAKO_ZENZAI_MODEL"];
        if (configured.length > 0) model = configured;
        if (helper && model) {
            _zenzai = std::make_unique<keynako::ZenzaiClient>(helper.UTF8String, model.UTF8String);
        }
    }
    if (_zenzai && _zenzai->available()) {
        std::string generated = _zenzai->generate(_session.reading());
        if (!generated.empty()) {
            _session.insert_zenzai_candidate(std::move(generated));
            return YES;
        }
    }
    return NO;
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *connection = [bundle objectForInfoDictionaryKey:@"InputMethodConnectionName"];
        gServer = [[IMKServer alloc] initWithName:connection bundleIdentifier:bundle.bundleIdentifier];
        gCandidates = [[IMKCandidates alloc] initWithServer:gServer
                                                  panelType:kIMKSingleColumnScrollingCandidatePanel];
        [gCandidates setDismissesAutomatically:NO];
        [NSApplication sharedApplication];
        [NSApp run];
    }
    return 0;
}
