# Copyright 2016 Raumfeld
#
# Distributed under the OSI-approved BSD License (the "License");
# see accompanying file LICENSE for details.
#
# This software is distributed WITHOUT ANY WARRANTY; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the License for more information.

# This is an example artifact, for use with the Artifactory.cmake CMake module.
#
# It builds ZLib from source using the CMake ExternalProject module, unless
# a prebuilt version is already found.
#
# FIXME: The use_prebuilt_artifact() and create_artifact() functions need to be
# moved into shared modules!

include(ExternalProject)

include(support/cmake/FindArtifactFile)

# These are set by the toplevel CMakeLists.txt.
get_property(ZLIB_GIT_REPOSITORY GLOBAL PROPERTY ZLIB_GIT_REPOSITORY)
get_property(ZLIB_GIT_VERSION GLOBAL PROPERTY ZLIB_GIT_VERSION)

set(ZLIB_INSTALL_DIR ${CMAKE_CURRENT_BINARY_DIR}/zlib-install)

# This is the output file that we need to create, so that Artifactory.cmake can
# generate a suitable 'artifactory-upload-zlib' target for it.
set(ARTIFACT_OUTPUT artifact-output/zlib-${ZLIB_GIT_VERSION}-SNAPSHOT.tar.gz)

# This is the file that Artifactory.cmake will create if it finds a prebuilt
# version of ZLib in the remote Artifactory server.
set(ARTIFACT_PREBUILT artifact-prebuilt/zlib-${ZLIB_GIT_VERSION}-*.tar.gz)

find_artifact_file(artifact_prebuilt "${ARTIFACT_PREBUILT}")

# ::
#
#     use_prebuilt_artifact(target_name
#                           PREBUILT_FILE <file>
#                           TARGET_FILE <file>
#                           [UNPACK_TAR_GZ]
#                           [UNPACK_DIRECTORY <dir>]
#                           [CHECK_FILES <file1> ...]
#                           [DEPENDS <dep> ...]
#                           )
#
# Helper function for using prebuilt artifacts.
#
# You can use this to create a symlink from the file in the artifact-prebuilt/
# directory (that Artifactory.cmake creates) to wherever things that depend on
# it would expect it to be (in the build directory).
#
# Optionally, this function also unpacks the artifact, if it's a .tar.gzl. This
# is normally what you want, as if an artifact depends on another artifact it
# most likely wants to link against or execute some file within a tree of files.
#
# Artifactory.cmake doesn't create anything in the build directory directly.
# It's important to keep a separation between 'prebuilt artifacts that were
# download' and 'artifacts that we built ourselves', so that Artifactory.cmake
# knows which ones need to be submitted (you shouldn't and probably can't
# resubmit something that you just fetched).
#
function(use_prebuilt_artifact target_name)
    set(options UNPACK_TAR_GZ)
    set(one_value_keywords PREBUILT_FILE TARGET_FILE UNPACK_DIRECTORY)
    set(multi_value_keywords CHECK_FILES DEPENDS)

    cmake_parse_arguments(ARTIFACT "${options}" "${one_value_keywords}"
        "${multi_value_keywords}" ${ARGN})
    ensure_all_arguments_parsed(use_prebuilt_artifact "${ARTIFACT_UNPARSED_ARGUMENTS}")
    require_arguments(use_prebuilt_artifact ARTIFACT PREBUILT_FILE)

    if(ARTIFACT_UNPACK_TAR_GZ)
        require_arguments(use_prebuilt_artifact ARTIFACT UNPACK_DIRECTORY)

        # We can't easily depend on the entire extracted tarball, so we create
        # a symlink to it first, which acts as a stamp and marker.
        set(intermediate ${CMAKE_CURRENT_BINARY_DIR}/${target_name}.tar.gz)

        if(NOT IS_ABSOLUTE ${ARTIFACT_UNPACK_DIRECTORY})
            set(ARTIFACT_UNPACK_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/${ARTIFACT_UNPACK_DIRECTORY})
        endif()

        file(MAKE_DIRECTORY ${ARTIFACT_UNPACK_DIRECTORY})

        add_custom_command(
            COMMAND
                cmake -E create_symlink ${ARTIFACT_PREBUILT_FILE} ${intermediate}
            COMMAND
                cmake -E tar -x -z ${intermediate}
            COMMAND
                ${CMAKE_SOURCE_DIR}/support/scripts/check-target-created-files
                    "${target_name}" ${intermediate} ${ARTIFACT_CHECK_FILES}
            OUTPUT
                ${intermediate} ${ARTIFACT_CHECK_FILES}
            DEPENDS
                "${ARTIFACT_DEPENDS}"
            WORKING_DIRECTORY
                ${ARTIFACT_UNPACK_DIRECTORY}
            COMMENT
                "Using prebuilt tar.gz archive of ${target_name}"
            )
    else()
        require_arguments(use_prebuilt_artifact ARTIFACT TARGET_FILE)

        if(NOT IS_ABSOLUTE ${ARTIFACT_TARGET_FILE})
            set(ARTIFACT_TARGET_FILE ${CMAKE_CURRENT_BINARY_DIR}/${ARTIFACT_TARGET_FILE})
        endif()

        get_filename_component(output_dir ${ARTIFACT_TARGET_FILE} DIRECTORY)
        file(MAKE_DIRECTORY ${ARTIFACT_TARGET_FILE})

        add_custom_command(
            COMMAND
                cmake -E create_symlink ${ARTIFACT_PREBUILT_FILE}
                    ${ARTIFACT_TARGET_FILE}
            OUTPUT
                ${ARTIFACT_TARGET_FILE}
            DEPENDS
                "${ARTIFACT_DEPENDS}"
            COMMENT
                "Using prebuilt version of ${target_name}"
            )

        add_custom_target(${target_name} DEPENDS ${ARTIFACT_TARGET_FILE})
    endif()
endfunction()

# ::
#
#     create_artifact(target_name
#                     OUTPUT_FILE <file>
#                     [TARGET_FILE <file]>
#                     [PACK_TAR_GZ]
#                     [PACK_DIRECTORY <dir>]
#                     [DEPENDS <dep> ...]
#                     )
#
# Helper function for creating artifacts from build output.
#
# You can do two things here. One is to symlink a specific file into place in
# the artifact-output/ directory, in which case you must pass TARGET_FILE (the
# built file) and OUTPUT_FILE (the name of the link to create in
# artifact-output/). The other is to pack a tree of files as a tar.gz archive,
# and link that into place. In this case you must set PACK_TAR_GZ,
# PACK_DIRECTORY and OUTPUT_FILE.
#
function(create_artifact target_name)
    set(options PACK_TAR_GZ)
    set(one_value_keywords OUTPUT_FILE PACK_DIRECTORY TARGET_FILE)
    set(multi_value_keywords DEPENDS)

    cmake_parse_arguments(ARTIFACT "${options}" "${one_value_keywords}"
        "${multi_value_keywords}" ${ARGN})
    ensure_all_arguments_parsed(create_artifact "${ARTIFACT_UNPARSED_ARGUMENTS}")
    require_arguments(create_artifact ARTIFACT OUTPUT_FILE)

    if(NOT IS_ABSOLUTE ${ARTIFACT_OUTPUT_FILE})
        set(ARTIFACT_OUTPUT_FILE ${CMAKE_CURRENT_BINARY_DIR}/${ARTIFACT_OUTPUT_FILE})
    endif()

    get_filename_component(artifact_dir ${ARTIFACT_OUTPUT_FILE} DIRECTORY)
    file(MAKE_DIRECTORY ${artifact_dir})

    if(ARTIFACT_PACK_TAR_GZ)
        require_arguments(create_artifact ARTIFACT PACK_DIRECTORY)

        # We can't easily depend on the entire extracted tarball, so we create
        # a symlink to it first, which acts as a stamp and marker.
        set(intermediate ${CMAKE_CURRENT_BINARY_DIR}/${target_name}.tar.gz)

        add_custom_command(
            OUTPUT
                ${intermediate} ${target_name}
            COMMAND
                cmake -E tar -c -z ${intermediate} .
            COMMAND
                cmake -E create_symlink ${intermediate} ${ARTIFACT_OUTPUT_FILE}
            DEPENDS
                ${target_name} ${ARTIFACT_DEPENDS}
            WORKING_DIRECTORY
                ${ARTIFACT_PACK_DIRECTORY}
            VERBATIM
        )
    else()
        require_arguments(create_artifact ARTIFACT TARGET_FILE)

        add_custom_command(
            OUTPUT
                ${ARTIFACT_OUTPUT_FILE}
            COMMAND
                cmake -E create_symlink ${ARTIFACT_TARGET_FILE} ${ARTIFACT_OUTPUT_FILE}
            DEPENDS
                ${ARTIFACT_TARGET_FILE} ${target_name} ${ARTIFACT_DEPENDS}
            )
    endif()
endfunction()

if(artifact_prebuilt)
    use_prebuilt_artifact(
        zlib
        PREBUILT_FILE ${artifact_prebuilt}
        UNPACK_TAR_GZ
        UNPACK_DIRECTORY ${ZLIB_INSTALL_DIR}
        CHECK_FILES zlib.h libz.so
        )
else()
    ExternalProject_Add(zlib
        GIT_REPOSITORY ${ZLIB_GIT_REPOSITORY}
        GIT_TAG ${ZLIB_GIT_VERSION}
        CONFIGURE_COMMAND ./configure
        INSTALL_COMMAND make DESTDIR=${ZLIB_INSTALL_DIR} install
        BUILD_IN_SOURCE 1
        )

    create_artifact(
        zlib
        OUTPUT_FILE ${ARTIFACT_OUTPUT}
        PACK_TAR_GZ
        PACK_DIRECTORY ${ZLIB_INSTALL_DIR}
        DEPENDS zlib
        )
endif()
