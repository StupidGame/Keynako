#include "keynako_improvement_submission.h"

#include <string>

int main() {
    const keynako::windows::ImprovementSubmission submission{
        "選択\"語", "よみ\\かた", 2};
    const std::string expected =
        "{\"word\":\"選択\\\"語\",\"ruby\":\"よみ\\\\かた\","
        "\"importance\":3,\"categories\":[],"
        "\"note\":\"IME候補改善: 第3候補を選択\","
        "\"source\":\"Keynako IME\",\"app_version\":\"1.0.0+7\"}";
    return keynako::windows::build_improvement_payload(submission, "1.0.0+7") == expected
        ? 0
        : 1;
}
