# UWP packaging for Xbox Dev Mode (and Windows sideloading).
#
# Targets:
#   dusklight_uwp_layout   Assembles build/<preset>/uwp/layout, a loose app layout that can be registered directly
#                          (built by default)
#   dusklight_uwp_check    Reports imports that may not resolve on Xbox (tools/uwp/check_imports.py)
#   dusklight_uwp_package  Packs and signs build/<preset>/uwp/Dusklight_<version>_<arch>.msix
include_guard(GLOBAL)

set(DUSK_UWP_EMBED_ISO "" CACHE FILEPATH
    "Disc image to embed in the UWP package as disc/game.iso. The image stays local to your build; never distribute the package.")
set(DUSK_UWP_IDENTITY_NAME "TwilitRealm.Dusklight" CACHE STRING "UWP package identity name")
set(DUSK_UWP_PUBLISHER "CN=Dusklight Developer" CACHE STRING
    "UWP package publisher; must match the subject of the signing certificate")
set(DUSK_UWP_PUBLISHER_DISPLAY_NAME "Twilit Realm" CACHE STRING "UWP package publisher display name")
set(DUSK_UWP_CERTIFICATE "" CACHE FILEPATH
    "PFX certificate to sign the UWP package with. When empty, a self-signed development certificate is generated.")
set(DUSK_UWP_CERTIFICATE_PASSWORD "dusklight" CACHE STRING "Password of DUSK_UWP_CERTIFICATE")
set(DUSK_UWP_VERSION_OVERRIDE "" CACHE STRING
    "UWP package version (a.b.c.d). Defaults to the app version. Updating an installed package requires a higher version.")

function(_dusk_uwp_find_crt_dirs out_var arch)
    if (CMAKE_BUILD_TYPE STREQUAL "Debug")
        set(_redist_subdir "onecore/debug_nonredist/${arch}")
        set(_crt_glob "Microsoft.VC*.DebugCRT")
    else ()
        set(_redist_subdir "onecore/${arch}")
        set(_crt_glob "Microsoft.VC*.CRT")
    endif ()
    set(_redist_root "$ENV{VCToolsRedistDir}")
    if (NOT _redist_root)
        message(FATAL_ERROR "DUSK_UWP: VCToolsRedistDir is not set. Configure from a Visual Studio developer shell.")
    endif ()
    file(GLOB _crt_dirs LIST_DIRECTORIES TRUE "${_redist_root}/${_redist_subdir}/${_crt_glob}")
    if (NOT _crt_dirs)
        message(FATAL_ERROR "DUSK_UWP: OneCore C++ runtime not found in ${_redist_root}/${_redist_subdir}")
    endif ()
    if (CMAKE_BUILD_TYPE STREQUAL "Debug")
        # The debug UCRT isn't part of the OS
        file(GLOB _ucrt_dirs LIST_DIRECTORIES TRUE "$ENV{UniversalCRTSdkDir}/bin/$ENV{UCRTVersion}/${arch}/ucrt")
        list(APPEND _crt_dirs ${_ucrt_dirs})
    endif ()
    set(${out_var} "${_crt_dirs}" PARENT_SCOPE)
endfunction()

function(setup_uwp_package target)
    if (CMAKE_SYSTEM_PROCESSOR STREQUAL "AMD64")
        set(_arch x64)
    elseif (CMAKE_SYSTEM_PROCESSOR STREQUAL "ARM64")
        set(_arch arm64)
    else ()
        message(FATAL_ERROR "DUSK_UWP: unsupported architecture ${CMAKE_SYSTEM_PROCESSOR}")
    endif ()
    if (CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "ARM64")
        set(_host_arch arm64)
    else ()
        set(_host_arch x64)
    endif ()

    # Package versions are four numbers of at most 65535
    string(REPLACE "." ";" _version_parts "${BOREALIS_APP_VERSION}")
    set(DUSK_UWP_VERSION "")
    foreach (_index RANGE 0 3)
        set(_part 0)
        list(LENGTH _version_parts _part_count)
        if (_index LESS _part_count)
            list(GET _version_parts ${_index} _part)
        endif ()
        if (_part GREATER 65535)
            set(_part 65535)
        endif ()
        list(APPEND DUSK_UWP_VERSION ${_part})
    endforeach ()
    list(JOIN DUSK_UWP_VERSION "." DUSK_UWP_VERSION)
    if (DUSK_UWP_VERSION_OVERRIDE)
        set(DUSK_UWP_VERSION "${DUSK_UWP_VERSION_OVERRIDE}")
    endif ()
    set(DUSK_UWP_ARCHITECTURE ${_arch})

    set(_uwp_dir "${CMAKE_BINARY_DIR}/uwp")
    set(_layout_dir "${_uwp_dir}/layout")
    set(_assets_dir "${_uwp_dir}/Assets")
    set(_manifest "${_uwp_dir}/AppxManifest.xml")
    set(_args_file "${_uwp_dir}/aurora-args.txt")
    configure_file("${CMAKE_SOURCE_DIR}/platforms/uwp/AppxManifest.xml.in" "${_manifest}" @ONLY)

    # aurora's UWP host reads extra command line arguments from aurora-args.txt (see aurora/lib/uwp/host.cpp).
    if (DUSK_UWP_EMBED_ISO)
        set(_dvd_path "{InstalledLocation}\\disc\\game.iso")
    else ()
        # Without an embedded image, the disc is read from the app's local data folder, which the Xbox Device Portal
        # can upload to (LocalAppData/<package>/LocalState).
        set(_dvd_path "{LocalFolder}\\game.iso")
    endif ()
    file(WRITE "${_args_file}.in" "# Extra command line arguments, one per line\n--dvd\n${_dvd_path}\n")
    configure_file("${_args_file}.in" "${_args_file}" COPYONLY)

    _dusk_uwp_find_crt_dirs(_crt_dirs ${_arch})
    # Passed through a single -D argument
    string(REPLACE ";" "|" _crt_dirs "${_crt_dirs}")

    set(_logo_script "${CMAKE_SOURCE_DIR}/platforms/uwp/Create-UwpLogos.ps1")
    set(_icon "${CMAKE_SOURCE_DIR}/res/icon.png")
    add_custom_command(
            OUTPUT "${_assets_dir}/Square150x150Logo.png"
            COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File "${_logo_script}"
            -InputPng "${_icon}" -OutputDir "${_assets_dir}"
            DEPENDS "${_icon}" "${_logo_script}"
            COMMENT "Generating UWP logos"
            VERBATIM
    )

    add_custom_target(dusklight_uwp_layout ALL
            COMMAND ${CMAKE_COMMAND}
            "-DEXE_DIR=$<TARGET_FILE_DIR:${target}>"
            "-DLAYOUT_DIR=${_layout_dir}"
            "-DRES_DIR=${CMAKE_SOURCE_DIR}/res"
            "-DMANIFEST=${_manifest}"
            "-DASSETS_DIR=${_assets_dir}"
            "-DARGS_FILE=${_args_file}"
            "-DCRT_DIRS=${_crt_dirs}"
            "-DISO=${DUSK_UWP_EMBED_ISO}"
            -P "${CMAKE_SOURCE_DIR}/cmake/UWPStageLayout.cmake"
            DEPENDS "${_assets_dir}/Square150x150Logo.png"
            COMMENT "Staging UWP layout in ${_layout_dir}"
            VERBATIM
    )
    add_dependencies(dusklight_uwp_layout ${target})

    # Import check
    find_package(Python3 COMPONENTS Interpreter)
    get_filename_component(_linker_dir "${CMAKE_LINKER}" DIRECTORY)
    find_program(DUSK_DUMPBIN dumpbin HINTS "${_linker_dir}")
    set(_sdk_lib_dir "$ENV{WindowsSdkDir}Lib/$ENV{WindowsSDKLibVersion}um/${_arch}")
    if (Python3_Interpreter_FOUND AND DUSK_DUMPBIN AND EXISTS "${_sdk_lib_dir}/WindowsApp.lib")
        add_custom_target(dusklight_uwp_check
                COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tools/uwp/check_imports.py"
                --dumpbin "${DUSK_DUMPBIN}" --sdk-lib-dir "${_sdk_lib_dir}" --strict "${_layout_dir}"
                DEPENDS dusklight_uwp_layout
                COMMENT "Checking UWP imports"
                VERBATIM
        )
    else ()
        message(WARNING "DUSK_UWP: Python, dumpbin or WindowsApp.lib not found; dusklight_uwp_check is unavailable")
    endif ()

    # Packing and signing
    find_program(DUSK_MAKEAPPX makeappx HINTS "$ENV{WindowsSdkVerBinPath}/${_host_arch}")
    find_program(DUSK_SIGNTOOL signtool HINTS "$ENV{WindowsSdkVerBinPath}/${_host_arch}")
    if (NOT DUSK_MAKEAPPX OR NOT DUSK_SIGNTOOL)
        message(WARNING "DUSK_UWP: makeappx or signtool not found; dusklight_uwp_package is unavailable")
        return()
    endif ()
    if (DUSK_UWP_CERTIFICATE)
        set(_certificate "${DUSK_UWP_CERTIFICATE}")
        set(_certificate_depends)
    else ()
        set(_certificate "${_uwp_dir}/dusklight-dev.pfx")
        set(_certificate_depends "${_certificate}")
        add_custom_command(
                OUTPUT "${_certificate}"
                COMMAND powershell -NoProfile -ExecutionPolicy Bypass
                -File "${CMAKE_SOURCE_DIR}/platforms/uwp/New-UwpDevCertificate.ps1"
                -Publisher "${DUSK_UWP_PUBLISHER}" -OutputPfx "${_certificate}"
                -Password "${DUSK_UWP_CERTIFICATE_PASSWORD}"
                DEPENDS "${CMAKE_SOURCE_DIR}/platforms/uwp/New-UwpDevCertificate.ps1"
                COMMENT "Generating self-signed UWP development certificate"
                VERBATIM
        )
    endif ()
    set(_package "${_uwp_dir}/Dusklight_${DUSK_UWP_VERSION}_${_arch}.msix")
    set(_package_depends dusklight_uwp_layout)
    if (TARGET dusklight_uwp_check)
        set(_package_depends dusklight_uwp_check)
    endif ()
    add_custom_target(dusklight_uwp_package
            COMMAND "${DUSK_MAKEAPPX}" pack /o /h SHA256 /d "${_layout_dir}" /p "${_package}"
            COMMAND "${DUSK_SIGNTOOL}" sign /q /fd SHA256 /f "${_certificate}" /p "${DUSK_UWP_CERTIFICATE_PASSWORD}"
            "${_package}"
            DEPENDS ${_certificate_depends}
            COMMENT "Packing and signing ${_package}"
            VERBATIM
    )
    add_dependencies(dusklight_uwp_package ${_package_depends})
endfunction()
