#import <Cocoa/Cocoa.h>
#import <InputMethodKit/InputMethodKit.h>

#include <algorithm>
#include <chrono>
#include <exception>
#include <filesystem>
#include <fstream>
#include <memory>
#include <string>
#include <utility>
#include <vector>

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
- (void)configureDictionaries;
- (void)reloadSharedDictionary:(BOOL)force;
- (void)selectJapaneseMode:(id)sender;
- (void)selectEnglishMode:(id)sender;
- (void)toggleLiveConversion:(id)sender;
@end

@implementation KeynakoInputController {
    keynako::ImeSession _session;
    std::unique_ptr<keynako::ZenzaiClient> _zenzai;
    BOOL _dictionariesConfigured;
    std::filesystem::path _sharedDictionaryPath;
    std::filesystem::file_time_type _sharedDictionaryWriteTime;
    std::chrono::steady_clock::time_point _lastDictionaryCheck;
}

- (BOOL)handleEvent:(NSEvent *)event client:(id)sender {
    if (event.type != NSEventTypeKeyDown) return NO;
    [self configureDictionaries];
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
    if (key == 102 || key == 104) {
        _session.set_mode(key == 102 ? keynako::InputMode::english : keynako::InputMode::japanese);
        [self cancelComposition:sender];
        return YES;
    }
    if (key == 51) {
        if (_session.raw_input().empty()) return NO;
        if (!_session.cancel_conversion()) _session.backspace();
        [self updateMarkedText:sender];
        return YES;
    }
    if (key == 53) {
        if (_session.raw_input().empty()) return NO;
        if (_session.cancel_conversion()) [self updateMarkedText:sender];
        else [self cancelComposition:sender];
        return YES;
    }
    if (key == 36 || key == 76) {
        if (_session.raw_input().empty()) return NO;
        [self commitCurrent:sender];
        return YES;
    }
    if (key == 49 || key == 125) {
        if (_session.raw_input().empty()) return NO;
        [self reloadSharedDictionary:NO];
        if (!_session.is_converting()) {
            if (key == 49 && _session.mode() == keynako::InputMode::japanese) [self addZenzai];
            _session.begin_conversion();
        } else {
            _session.select_next();
        }
        [self updateMarkedText:sender];
        return YES;
    }
    if (key == 126) {
        if (_session.raw_input().empty()) return NO;
        if (!_session.is_converting()) _session.begin_conversion();
        _session.select_previous();
        [self updateMarkedText:sender];
        return YES;
    }

    NSString *characters = event.charactersIgnoringModifiers.lowercaseString;
    if (characters.length != 1) return NO;
    const unichar scalar = [characters characterAtIndex:0];
    const BOOL accepted = (scalar >= 'a' && scalar <= 'z') || scalar == '-' || scalar == ',' || scalar == '.';
    if (!accepted) return NO;
    if (_session.mode() == keynako::InputMode::english) return NO;
    [self reloadSharedDictionary:NO];
    _session.append_ascii(static_cast<char>(scalar));
    [self updateMarkedText:sender];
    return YES;
}

- (NSMenu *)menu {
    [self configureDictionaries];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Keynako"];

    NSMenuItem *japanese = [[NSMenuItem alloc] initWithTitle:@"ひらがな (あ)"
                                                     action:@selector(selectJapaneseMode:)
                                              keyEquivalent:@""];
    japanese.target = self;
    japanese.state = _session.mode() == keynako::InputMode::japanese
        ? NSControlStateValueOn
        : NSControlStateValueOff;
    [menu addItem:japanese];

    NSMenuItem *english = [[NSMenuItem alloc] initWithTitle:@"英数 (A)"
                                                    action:@selector(selectEnglishMode:)
                                             keyEquivalent:@""];
    english.target = self;
    english.state = _session.mode() == keynako::InputMode::english
        ? NSControlStateValueOn
        : NSControlStateValueOff;
    [menu addItem:english];

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *live = [[NSMenuItem alloc] initWithTitle:@"ライブ変換"
                                                 action:@selector(toggleLiveConversion:)
                                          keyEquivalent:@""];
    live.target = self;
    live.state = _session.live_conversion()
        ? NSControlStateValueOn
        : NSControlStateValueOff;
    [menu addItem:live];
    return menu;
}

- (void)selectJapaneseMode:(id)sender {
    (void)sender;
    _session.set_mode(keynako::InputMode::japanese);
    id client = [self client];
    if (client && !_session.raw_input().empty()) [self cancelComposition:client];
}

- (void)selectEnglishMode:(id)sender {
    (void)sender;
    _session.set_mode(keynako::InputMode::english);
    id client = [self client];
    if (client && !_session.raw_input().empty()) [self cancelComposition:client];
}

- (void)toggleLiveConversion:(id)sender {
    (void)sender;
    _session.set_live_conversion(!_session.live_conversion());
    id client = [self client];
    if (client && !_session.raw_input().empty()) [self updateMarkedText:client];
}

- (NSArray *)candidates:(id)sender {
    [self configureDictionaries];
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
    if (_session.is_converting()) {
        [gCandidates updateCandidates];
        [gCandidates show:kIMKLocateCandidatesBelowHint];
    } else {
        [gCandidates hide];
    }
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

- (void)configureDictionaries {
    if (_dictionariesConfigured) return;
    _dictionariesConfigured = YES;
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *root = [bundle pathForResource:@"Dictionary" ofType:nil
                                  inDirectory:@"azookey_dictionary"];
    if (root.length > 0) _session.set_bundled_dictionary_path(root.UTF8String);
    [self reloadSharedDictionary:YES];
}

- (void)reloadSharedDictionary:(BOOL)force {
    const auto now = std::chrono::steady_clock::now();
    if (!force && _lastDictionaryCheck.time_since_epoch().count() != 0 &&
        now - _lastDictionaryCheck < std::chrono::seconds(5)) return;
    _lastDictionaryCheck = now;

    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    [paths addObject:[NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Application Support/Keynako/shared_dictionary.tsv"]];
    NSString *bundled = [[NSBundle mainBundle] pathForResource:@"bundled_shared_dictionary"
                                                        ofType:@"tsv"];
    if (bundled.length > 0) [paths addObject:bundled];

    for (NSString *pathValue in paths) {
        const std::filesystem::path path(pathValue.UTF8String);
        std::error_code error;
        if (!std::filesystem::exists(path, error) || error) continue;
        const auto writeTime = std::filesystem::last_write_time(path, error);
        if (error) continue;
        if (path == _sharedDictionaryPath && writeTime == _sharedDictionaryWriteTime) return;

        std::ifstream stream(path, std::ios::binary);
        if (!stream) continue;
        std::vector<keynako::DictionaryEntry> entries;
        std::string line;
        bool validHeader = false;
        while (std::getline(stream, line)) {
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (line.rfind("# keynako-shared-dictionary-v1", 0) == 0) {
                validHeader = true;
                continue;
            }
            if (line.empty() || line.front() == '#') continue;
            const auto firstTab = line.find('\t');
            const auto secondTab = firstTab == std::string::npos
                ? std::string::npos
                : line.find('\t', firstTab + 1);
            if (firstTab == std::string::npos || secondTab == std::string::npos) continue;
            try {
                const int importance = std::clamp(std::stoi(line.substr(0, firstTab)), 1, 5);
                std::string reading = line.substr(firstTab + 1, secondTab - firstTab - 1);
                const auto thirdTab = line.find('\t', secondTab + 1);
                std::string value = thirdTab == std::string::npos
                    ? line.substr(secondTab + 1)
                    : line.substr(secondTab + 1, thirdTab - secondTab - 1);
                if (!reading.empty() && !value.empty()) {
                    keynako::DictionaryEntry entry{std::move(reading), std::move(value), importance};
                    if (thirdTab != std::string::npos) {
                        const auto fourthTab = line.find('\t', thirdTab + 1);
                        const auto fifthTab = fourthTab == std::string::npos
                            ? std::string::npos
                            : line.find('\t', fourthTab + 1);
                        if (fourthTab != std::string::npos && fifthTab != std::string::npos) {
                            entry.word_weight = std::stof(line.substr(thirdTab + 1, fourthTab - thirdTab - 1));
                            entry.lcid = std::stoi(line.substr(fourthTab + 1, fifthTab - fourthTab - 1));
                            entry.rcid = std::stoi(line.substr(fifthTab + 1));
                            entry.has_word_weight = true;
                        }
                    }
                    entries.push_back(std::move(entry));
                }
            } catch (const std::exception &) {
                continue;
            }
        }
        if (!validHeader || entries.empty()) continue;
        _session.set_user_dictionary(std::move(entries));
        _sharedDictionaryPath = path;
        _sharedDictionaryWriteTime = writeTime;
        return;
    }
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
