cmake_minimum_required(VERSION 3.28)

file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" KINETIC_VERSION LIMIT_COUNT 1)
project(Kinetic VERSION ${KINETIC_VERSION} LANGUAGES C CXX OBJCXX)

if(NOT APPLE)
    message(FATAL_ERROR "Kinetic currently supports macOS only")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "Supported architecture" FORCE)
set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0 CACHE STRING "Minimum macOS version" FORCE)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(KINETIC_GITHUB_CLIENT_ID "Ov23li0CaegWQ9lfPBQl" CACHE STRING "Public GitHub OAuth client ID")
if(NOT KINETIC_GITHUB_CLIENT_ID)
    set(KINETIC_GITHUB_CLIENT_ID "Ov23li0CaegWQ9lfPBQl")
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Release")
    set(KINETIC_CARGO_PROFILE release)
    set(KINETIC_CARGO_ARGS --release)
else()
    set(KINETIC_CARGO_PROFILE debug)
    set(KINETIC_CARGO_ARGS)
endif()

set(KINETIC_CARGO_TARGET_DIR "${CMAKE_BINARY_DIR}/cargo")
set(KINETIC_RUSTFLAGS
    "--remap-path-prefix=$ENV{HOME}=/build-user --remap-path-prefix=${CMAKE_SOURCE_DIR}=/kinetic")
set(KINETIC_RUST_LIBRARY
    "${KINETIC_CARGO_TARGET_DIR}/${KINETIC_CARGO_PROFILE}/libkinetic_backend.a")

set(KINETIC_CPP_PLUGIN_DIR "${CMAKE_BINARY_DIR}/cpp-support-cargo")
set(KINETIC_CPP_PLUGIN
    "${KINETIC_CPP_PLUGIN_DIR}/${KINETIC_CARGO_PROFILE}/libkineticCppSupport.dylib")
set_source_files_properties("${KINETIC_CPP_PLUGIN}" PROPERTIES
    GENERATED TRUE MACOSX_PACKAGE_LOCATION "PlugIns")
add_custom_command(
    OUTPUT "${KINETIC_CPP_PLUGIN}"
    COMMAND "${CMAKE_COMMAND}" -E env "CARGO_TARGET_DIR=${KINETIC_CPP_PLUGIN_DIR}"
            "RUSTFLAGS=${KINETIC_RUSTFLAGS}"
            cargo build --offline --manifest-path
            "${CMAKE_SOURCE_DIR}/plugins/builtin/cppSupport/Cargo.toml" ${KINETIC_CARGO_ARGS}
    DEPENDS
        "${CMAKE_SOURCE_DIR}/plugins/builtin/cppSupport/Cargo.toml"
        "${CMAKE_SOURCE_DIR}/plugins/builtin/cppSupport/Cargo.lock"
        "${CMAKE_SOURCE_DIR}/plugins/builtin/cppSupport/src/lib.rs"
        "${CMAKE_SOURCE_DIR}/plugins/builtin/cppSupport/src/language.rs"
        "${CMAKE_SOURCE_DIR}/plugins/builtin/cppSupport/src/lsp.rs"
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    COMMENT "Building the bundled C/C++ Support plugin"
    VERBATIM)
add_custom_target(kinetic_cpp_support DEPENDS "${KINETIC_CPP_PLUGIN}")

add_custom_command(
    OUTPUT "${KINETIC_RUST_LIBRARY}"
    COMMAND
        "${CMAKE_COMMAND}" -E env
        "CARGO_TARGET_DIR=${KINETIC_CARGO_TARGET_DIR}"
        "RUSTFLAGS=${KINETIC_RUSTFLAGS}"
        cargo build --manifest-path "${CMAKE_SOURCE_DIR}/Cargo.toml" ${KINETIC_CARGO_ARGS}
    DEPENDS
        "${CMAKE_SOURCE_DIR}/Cargo.toml"
        "${CMAKE_SOURCE_DIR}/src/Rust/backend/Cargo.toml"
        "${CMAKE_SOURCE_DIR}/src/Rust/backend/src/lib.rs"
        "${CMAKE_SOURCE_DIR}/src/Rust/backend/src/document.rs"
        "${CMAKE_SOURCE_DIR}/src/Rust/backend/src/extensions.rs"
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    COMMENT "Building Kinetic's Rust backend"
    VERBATIM)

add_custom_target(kinetic_backend_build DEPENDS "${KINETIC_RUST_LIBRARY}")

add_library(kinetic_backend STATIC IMPORTED GLOBAL)
set_target_properties(kinetic_backend PROPERTIES IMPORTED_LOCATION "${KINETIC_RUST_LIBRARY}")
add_dependencies(kinetic_backend kinetic_backend_build)

set(KINETIC_APP_ICON "${CMAKE_SOURCE_DIR}/assets/icons/Kinetic.icns")
set_source_files_properties("${KINETIC_APP_ICON}" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)

add_executable(
    Kinetic MACOSX_BUNDLE src/C++/app/main.mm src/C++/app/githubAccount.mm
                              src/C++/app/keyboardShortcuts.mm
                              src/C++/app/pluginHost.mm src/C++/app/workspaceSearch.mm
                              src/C++/ui/activityBar.mm src/C++/ui/contextMenu.mm
                              src/C++/ui/editorView.mm
                              src/C++/ui/editorStructure.mm
                              src/C++/ui/fileDialog.mm
                              src/C++/ui/homeView.mm
                              src/C++/ui/searchPopover.mm
                              src/C++/ui/syntaxHighlight.mm
                              src/C++/ui/trafficBar.mm src/C++/ui/tween.mm
                              "${KINETIC_APP_ICON}" "${KINETIC_CPP_PLUGIN}")
target_include_directories(Kinetic PRIVATE include src/C++/app src/C++/bridge src/C++/ui)
target_compile_options(Kinetic PRIVATE "-fobjc-arc")
target_link_libraries(
    Kinetic PRIVATE kinetic_backend "-framework AppKit" "-framework Metal" "-framework MetalKit"
                           "-framework Security")
set_target_properties(
    Kinetic
    PROPERTIES
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/cmake/Info.plist.in"
        OUTPUT_NAME Kinetic)

add_executable(kinetic_cli src/C++/app/cli.cpp)
target_include_directories(kinetic_cli PRIVATE src/C++/bridge)
target_link_libraries(kinetic_cli PRIVATE kinetic_backend)
set_target_properties(kinetic_cli PROPERTIES OUTPUT_NAME kinetic)

add_custom_command(
    TARGET Kinetic
    POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory
            "$<TARGET_BUNDLE_DIR:Kinetic>/Contents/Resources/bin"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "$<TARGET_FILE:kinetic_cli>"
            "$<TARGET_BUNDLE_DIR:Kinetic>/Contents/Resources/bin/kinetic"
    COMMENT "Embedding the Kinetic CLI")
add_dependencies(Kinetic kinetic_cli kinetic_cpp_support)
add_custom_target(
    kinetic_sign_bundle ALL
    COMMAND codesign --force --sign -
            "$<TARGET_BUNDLE_DIR:Kinetic>/Contents/PlugIns/libkineticCppSupport.dylib"
    COMMAND codesign --force --sign -
            "$<TARGET_BUNDLE_DIR:Kinetic>/Contents/Resources/bin/kinetic"
    COMMAND codesign --force --sign - "$<TARGET_BUNDLE_DIR:Kinetic>"
    DEPENDS Kinetic
    COMMENT "Signing the completed Kinetic app bundle"
    VERBATIM)

enable_testing()
add_test(NAME kinetic_cli_version COMMAND kinetic_cli --version)
set_tests_properties(kinetic_cli_version PROPERTIES PASS_REGULAR_EXPRESSION "kinetic ${PROJECT_VERSION}")

add_executable(kineticDocumentBackendTests tests/documentBackendTests.cpp)
target_include_directories(kineticDocumentBackendTests PRIVATE src/C++/bridge)
target_link_libraries(kineticDocumentBackendTests PRIVATE kinetic_backend)
add_test(NAME kineticDocumentBackend COMMAND kineticDocumentBackendTests)

add_executable(kineticEditorBackendIntegrationTests
    tests/editorBackendIntegrationTests.mm
    src/C++/ui/editorView.mm src/C++/ui/activityBar.mm src/C++/ui/contextMenu.mm
    src/C++/ui/editorStructure.mm src/C++/ui/searchPopover.mm src/C++/ui/syntaxHighlight.mm
    src/C++/ui/tween.mm src/C++/app/workspaceSearch.mm)
target_include_directories(kineticEditorBackendIntegrationTests PRIVATE
    include src/C++/app src/C++/bridge src/C++/ui)
target_compile_options(kineticEditorBackendIntegrationTests PRIVATE "-fobjc-arc")
target_link_libraries(kineticEditorBackendIntegrationTests PRIVATE kinetic_backend "-framework AppKit")
add_test(NAME kineticEditorBackendIntegration COMMAND kineticEditorBackendIntegrationTests)

add_executable(kineticWorkspaceSearchTests tests/workspaceSearchTests.mm
                                           src/C++/app/workspaceSearch.mm)
target_include_directories(kineticWorkspaceSearchTests PRIVATE src/C++/app)
target_compile_options(kineticWorkspaceSearchTests PRIVATE "-fobjc-arc")
target_link_libraries(kineticWorkspaceSearchTests PRIVATE "-framework Foundation")
add_test(NAME kineticWorkspaceSearch COMMAND kineticWorkspaceSearchTests)

add_executable(kineticSyntaxHighlightTests tests/syntaxHighlightTests.mm
                                          src/C++/ui/syntaxHighlight.mm)
target_include_directories(kineticSyntaxHighlightTests PRIVATE src/C++/ui)
target_compile_options(kineticSyntaxHighlightTests PRIVATE "-fobjc-arc")
target_link_libraries(kineticSyntaxHighlightTests PRIVATE "-framework Foundation")
add_test(NAME kineticSyntaxHighlight COMMAND kineticSyntaxHighlightTests)

add_executable(kineticEditorStructureTests tests/editorStructureTests.mm
                                           src/C++/ui/editorStructure.mm)
target_include_directories(kineticEditorStructureTests PRIVATE src/C++/ui)
target_compile_options(kineticEditorStructureTests PRIVATE "-fobjc-arc")
target_link_libraries(kineticEditorStructureTests PRIVATE "-framework Foundation")
add_test(NAME kineticEditorStructure COMMAND kineticEditorStructureTests)

add_executable(kineticFileDialogTests tests/fileDialogTests.mm src/C++/ui/fileDialog.mm
                                      src/C++/ui/contextMenu.mm)
target_include_directories(kineticFileDialogTests PRIVATE src/C++/ui)
target_compile_options(kineticFileDialogTests PRIVATE "-fobjc-arc")
target_link_libraries(kineticFileDialogTests PRIVATE "-framework AppKit")
add_test(NAME kineticFileDialog COMMAND kineticFileDialogTests)

add_library(kineticSamplePlugin MODULE tests/samplePlugin.cpp)
target_include_directories(kineticSamplePlugin PRIVATE include)
set_target_properties(kineticSamplePlugin PROPERTIES PREFIX "" SUFFIX ".dylib")

add_executable(kineticPluginHostTests tests/pluginHostTests.mm src/C++/app/pluginHost.mm)
target_include_directories(kineticPluginHostTests PRIVATE include src/C++/app src/C++/bridge)
target_compile_options(kineticPluginHostTests PRIVATE "-fobjc-arc")
target_link_libraries(kineticPluginHostTests PRIVATE kinetic_backend "-framework AppKit")
add_dependencies(kineticPluginHostTests kineticSamplePlugin)
add_test(NAME kineticPluginHost COMMAND kineticPluginHostTests "$<TARGET_FILE_DIR:kineticSamplePlugin>")

add_executable(kineticCppSupportPluginTests tests/cppSupportPluginTests.mm src/C++/app/pluginHost.mm)
target_include_directories(kineticCppSupportPluginTests PRIVATE include src/C++/app src/C++/bridge)
target_compile_options(kineticCppSupportPluginTests PRIVATE "-fobjc-arc")
target_link_libraries(kineticCppSupportPluginTests PRIVATE kinetic_backend "-framework AppKit")
add_dependencies(kineticCppSupportPluginTests kinetic_cpp_support)
add_test(NAME kineticCppSupportPlugin COMMAND kineticCppSupportPluginTests
    "${KINETIC_CPP_PLUGIN_DIR}/${KINETIC_CARGO_PROFILE}")

add_executable(kineticGitHubAccountTests tests/githubAccountTests.mm
                                         src/C++/app/githubAccount.mm)
target_include_directories(kineticGitHubAccountTests PRIVATE src/C++/app)
target_compile_options(kineticGitHubAccountTests PRIVATE "-fobjc-arc")
target_link_libraries(kineticGitHubAccountTests PRIVATE "-framework AppKit" "-framework Security")
add_test(NAME kineticGitHubAccount COMMAND kineticGitHubAccountTests)
