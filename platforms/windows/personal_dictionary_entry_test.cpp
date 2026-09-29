#include "personal_dictionary_entry.h"

#include <optional>
#include <string>

int main() {
    using keynako::windows::PersonalEntryUpdateStatus;
    using keynako::windows::prepare_personal_entry_update;

    const auto first = prepare_personal_entry_update(
        std::nullopt, "にほんご", "日本語");
    if (first.status != PersonalEntryUpdateStatus::added ||
        first.content != "# keynako-shared-dictionary-v1\tlocal\t1\tmanual\n"
                         "3\tにほんご\t日本語\n") return 1;

    const auto duplicate = prepare_personal_entry_update(
        first.content, "にほんご", "日本語");
    if (duplicate.status != PersonalEntryUpdateStatus::already_exists ||
        duplicate.content != first.content) return 2;

    const auto second = prepare_personal_entry_update(
        first.content, "かな", "仮名");
    if (second.status != PersonalEntryUpdateStatus::added ||
        second.content != first.content + "3\tかな\t仮名\n") return 3;

    const std::string existing =
        "# keynako-shared-dictionary-v1\tlocal\t1\tdate\r\n"
        "5\tよみ\t語\t-7.5\t1\t2\r\n";
    const auto preserved = prepare_personal_entry_update(
        existing, "かな", "仮名");
    if (preserved.status != PersonalEntryUpdateStatus::added ||
        preserved.content.substr(0, existing.size()) != existing) return 4;
    if (prepare_personal_entry_update(existing, "よみ", "語").status !=
        PersonalEntryUpdateStatus::already_exists) return 5;
    if (prepare_personal_entry_update("broken", "かな", "仮名").status !=
        PersonalEntryUpdateStatus::invalid) return 6;
    if (prepare_personal_entry_update(std::nullopt, "かな\nbad", "仮名").status !=
        PersonalEntryUpdateStatus::invalid) return 7;
    return 0;
}
