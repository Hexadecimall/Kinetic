#include "kineticBackend.h"

#include <cstring>
#include <iostream>
#include <string_view>

namespace {

void printHelp() {
    std::cout << "Kinetic " << kineticBackendVersion() << '\n'
              << "\n"
              << "Usage: kinetic [option] [path]\n"
              << "\n"
              << "Options:\n"
              << "  --help       Show this help\n"
              << "  --version    Show the version\n";
}

} // namespace

int main(int argc, char** argv) {
    if (argc == 1 || std::string_view(argv[1]) == "--help" || std::string_view(argv[1]) == "-h") {
        printHelp();
        return 0;
    }

    if (std::string_view(argv[1]) == "--version" || std::string_view(argv[1]) == "-V") {
        std::cout << "kinetic " << kineticBackendVersion() << " (ABI " << kineticBackendAbiVersion()
                  << ")\n";
        return 0;
    }

    std::cerr << "kinetic: opening paths is not implemented yet\n";
    return 2;
}
