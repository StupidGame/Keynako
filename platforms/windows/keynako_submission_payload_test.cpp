#include "keynako_submission_payload.h"

#include <string>

int main() {
    const std::string payload =
        keynako::windows::shared_candidate_payload("candidate\"", "read\ning");
    if (payload.find("\"word\":\"candidate\\\"\"") == std::string::npos) return 1;
    if (payload.find("\"ruby\":\"read\\ning\"") == std::string::npos) return 2;
    if (payload.find("\"importance\":3") == std::string::npos) return 3;
    if (payload.find("\"source\":\"Keynako\"") == std::string::npos) return 4;
    return 0;
}
