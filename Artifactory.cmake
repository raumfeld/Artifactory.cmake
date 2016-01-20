# Artifactory.cmake: CMake Integration with the Artifactory artifact server.
#
# Copyright 2016 Raumfeld
#
# Distributed under the OSI-approved BSD License (the "License");
# see accompanying file LICENSE for details.
#
# This software is distributed WITHOUT ANY WARRANTY; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the License for more information.

include("support/cmake/DefaultValue")
include("support/cmake/EnsureAllArgumentsParsed")
include("support/cmake/RequireArguments")

set(ARTIFACTORY_FETCH OFF CACHE BOOL "Whether to try to use prebuilt artifacts from Artifactory")
set(ARTIFACTORY_SUBMIT OFF CACHE BOOL "Whether to try to submit built artifact to Artifactory")

set(ARTIFACTORY_ALWAYS_BUILD "" CACHE LIST "List of artifacts that should always be built, even if prebuilt artifacts are available")

set(ARTIFACTORY_CACHE_DIR "${CMAKE_CURRENT_BINARY_DIR}/artifactory" CACHE STRING "Storage location for Artifactory artifacts")
mark_as_advanced(ARTIFACTORY_CACHE_DIR)

if(ARTIFACTORY_FETCH OR ARTIFACTORY_SUBMIT)
    find_program(ARTIFACTORY_CLI art REQUIRED)

    if(NOT ARTIFACTORY_CLI)
        message(FATAL_ERROR
            "Artifactory integration requires the `art` Artifactory "
            "commandline client. It is available at: "
            "https://github.com/JFrogDev/artifactory-cli-go. If it is "
            "available but not present in PATH, please use define the "
            "ARTIFACTORY_CLI variable to the location of the program.")
    endif()

    file(MAKE_DIRECTORY ${ARTIFACTORY_CACHE_DIR})
endif()

if(ARTIFACTORY_SUBMIT)
    add_custom_target(artifactory-submit)

    add_custom_target(artifactory-clean)
endif()

# ::
#
#    artifactory_add_artifact(<directory>
#                             LOCAL_TARGET <target-name>
#                             REPO <repo>
#                             GROUP <group-id>
#                             NAME <artifact-id>
#                             VERSION <version>
#                             UPLOAD_VERSION <upload-version>
#                             [IDENTITY_PROPERTIES <prop1> <value1> <prop2> <value2> ...]
#                             [INFORMATION_PROPERTIES <prop1> <value1> <prop2> <value2> ...])
#
# Add a CMakeLists.txt from <directory> that produces a Maven-style artifact.
#
# The subdirectory's CMakeLists.txt should add a target named <target-name>.
# This target should produce a Maven-style artifact, in subdirectory
# ${CMAKE_CURRENT_BINARY_DIR}/<directory>/artifact-output/.
#
# A Maven-style artifact consists of a 'main' artifact file, and optionally
# some supplementary files. They must follow the following naming scheme:
#
#   <artifact-id>-<version>[-<classifier>].<extension>
#
# If ARTIFACTORY_FETCH is ON, this command will use the `art` tool to check the
# configured Artifactory repo for the artifact. If it exists, the files will be
# copied into the ${CMAKE_CURRENT_BINARY_DIR}/<directory>/artifact-prebuilt/
# directory, before `add_subdirectory(<directory>)` is called. The target
# contained in the CMakeLists.txt there should check for the existance of that
# file, and if it already exists, make <target-name> be a target that just
# copies/unpacks the prebuilt artifact into place, instead of building it as
# it normally would.
#
# If ARTIFACTORY_FETCH is OFF, `add_subdirectory(<directory>)` is called right
# away.
#
# If ARTIFACTORY_SUBMIT is ON, then after `add_subdirectory(<directory>)` has
# been called, a target is created that depends on <target-name>, named
# `artifactory-upload-<target-name>`. This will upload all files from
# ${CMAKE_CURRENT_BINARY_DIR}/<directory>/artifact-output/ to the configured
# Artifactory repo using the `art` tool.
#
# If <version> ends with the string -SNAPSHOT, that is replaced with -* when
# looking for artifacts to fetch. The artifacts fetched into the
# artifact-prebuilt/ directory will contain the real version string (something
# like foo-1.0-20150125-1.tar.gz rather than foo-1.0-SNAPSHOT.tar.gz), so to
# make use of them, you need to match against the end of the filenames to
# work out which is which (e.g. *.tar.gz to match the main artifact, *-docs.txt
# to match some documentation artifact, etc.).
#
# If IDENTITY_PROPERTIES is set, those properties are attached to artifacts that are
# submitted, and are used to filter the artifacts when fetching. You can use
# this to ensure that artifact caching does not affect the reproducability of
# your builds. A good approach is to attach the commit SHA1 of the source repo
# being built as a property, and ensure that artifact caching is disabled
# unless the source tree is clean. That way, as long as the actual build of
# that artifact is reproducible given the same source code, there should be
# no difference using a prebuilt version of the artifact compared to building
# it yourself. Except that one is faster than the other, of course!
#
# If INFORMATION_PROPERTIES is set, those properties are attached to artifacts, but
# will not be used to filter the artifacts when fetching. This is used to
# upload build-specific properties with an artifact, such that it is possible
# to identify the build that created the artifact.
#
# Sounds complex? It is, sorry about that. As far as I know this is the first
# time someone has implemented artifact caching in CMake at all. You may find
# it useful to read about how Maven works, and how Artifactory's Maven2
# repository layout works.
#
function(artifactory_add_artifact directory)
    set(one_value_keywords GROUP LOCAL_TARGET NAME REPO VERSION UPLOAD_VERSION)
    set(multi_value_keywords IDENTITY_PROPERTIES INFORMATION_PROPERTIES)
    cmake_parse_arguments(ARTIFACT "" "${one_value_keywords}" "${multi_value_keywords}" ${ARGN})
    ensure_all_arguments_parsed(artifactory_add_artifact "${ARTIFACT_UNPARSED_ARGUMENTS}")
    require_arguments(artifactory_add_artifact ARTIFACT GROUP NAME REPO VERSION UPLOAD_VERSION)
    _artifactory_check_version(${ARTIFACT_VERSION})

    set(binary_directory ${CMAKE_CURRENT_BINARY_DIR}/${directory})

    list(FIND ARTIFACTORY_ALWAYS_BUILD ${ARTIFACT_NAME} always_build)
    if(${always_build} EQUAL -1)
        set(always_build FALSE)
    else()
        set(always_build TRUE)
        message(STATUS "    - Forcing local build of ${ARTIFACT_NAME}")
    endif()

    if(ARTIFACTORY_FETCH AND NOT ${always_build})
        artifactory_fetch(prebuilt_artifact_files
            REPO ${ARTIFACT_REPO}
            GROUP ${ARTIFACT_GROUP}
            NAME ${ARTIFACT_NAME}
            VERSION ${ARTIFACT_VERSION}
            PROPERTIES ${ARTIFACT_IDENTITY_PROPERTIES}
        )
    endif()

    if(prebuilt_artifact_files)
        # There's a prebuilt artifact: use it!
        file(MAKE_DIRECTORY ${binary_directory}/artifact-prebuilt/)
        foreach(file ${prebuilt_artifact_files})
            get_filename_component(file_name ${file} NAME)
            execute_process(
                COMMAND cmake -E create_symlink ${file} ${binary_directory}/artifact-prebuilt/${file_name})
        endforeach()
    endif()

    # The CMakeLists.txt in the subdirectory will hopefully pay attention
    # to the files in artifact-prebuilt/ and avoid building anything if
    # there is a prebuilt artifact supplied.
    add_subdirectory(${directory})

    if(NOT prebuilt_artifact_files)
        if(ARTIFACTORY_SUBMIT)
            artifactory_upload(
                artifactory-upload-${ARTIFACT_NAME}
                LOCAL_DIRECTORY ${binary_directory}/artifact-output
                LOCAL_TARGET ${ARTIFACT_LOCAL_TARGET}
                REPO ${ARTIFACT_REPO}
                GROUP ${ARTIFACT_GROUP}
                NAME ${ARTIFACT_NAME}
                VERSION ${ARTIFACT_VERSION}
                UPLOAD_VERSION ${ARTIFACT_UPLOAD_VERSION}
                PROPERTIES ${ARTIFACT_IDENTITY_PROPERTIES} ${ARTIFACT_INFORMATION_PROPERTIES}
                )

            add_dependencies(
                artifactory-submit artifactory-upload-${ARTIFACT_NAME}
                )

            add_custom_target(
                artifactory-clean-${ARTIFACT_NAME}
                COMMAND rm -f ${binary_directory}/artifact-output/*
                COMMENT "Removing artifacts for ${ARTIFACT_NAME}"
                )

            add_dependencies(
                artifactory-clean artifactory-clean-${ARTIFACT_NAME}
                )
        endif()
    endif()
endfunction()


# ::
#
#    artifactory_fetch(<result_var>
#                      REPO <repo>
#                      GROUP <group-id>
#                      NAME <artifact-id>
#                      VERSION <version>
#                      [PROPERTIES <prop1> <value1> <prop2> <value2> ...])
#
# Checks for a prebuilt version of an artifact in Artifactory, if the
# ARTIFACTORY_FETCH option is ON.
#
# This command executes at configure-time (when `cmake` itself is run). If the
# artifact is found, it is downloaded inside ${ARTIFACTORY_CACHE_DIR}, and
# <result_var> is set to the list of files that make up the artifact. If it is
# not found, <result_var> will be unset.
#
# If the <version> string ends with -SNAPSHOT, it will be replaced with -* in
# the resulting filename. This lets you use unreleased snapshot versions of the
# artifacts. If there are multiple snapshots for a given version, the latest
# one is chosen.
#
# The <classifier> and <extension> fields are glob patterns that allow you to
# limit which of the artifact files are downloaded. They default to '*', which
# means that all of the files are fetched.
#
set_property(GLOBAL PROPERTY _artifactory_fetch_message_printed 0)
function(artifactory_fetch result_var)
    # FIXME: please tidy this code up a bit!
    if(NOT ARTIFACTORY_FETCH)
        return()
    endif()

    set(one_value_keywords CLASSIFIER EXTENSION GROUP NAME REPO VERSION)
    set(multi_value_keywords PROPERTIES)
    cmake_parse_arguments(ARTIFACT "" "${one_value_keywords}" "${multi_value_keywords}" ${ARGN})

    ensure_all_arguments_parsed(artifactory_fetch "${ARTIFACT_UNPARSED_ARGUMENTS}")
    require_arguments(artifactory_fetch ARTIFACT GROUP NAME REPO VERSION)
    default_value(ARTIFACT_CLASSIFIER *)
    default_value(ARTIFACT_EXTENSION *)
    _artifactory_check_version(${ARTIFACT_VERSION})

    if(ARTIFACT_PROPERTIES)
        _artifactory_parse_properties(props_string "${ARTIFACT_PROPERTIES}")
        set(extra_args --props=${props_string})
    else()
        set(extra_args)
    endif()

    _artifactory_calculate_path_and_filename(
        remote_path remote_filename ${ARTIFACT_GROUP} ${ARTIFACT_NAME} ${ARTIFACT_VERSION} "*" "*" TRUE
    )

    get_property(message_printed GLOBAL PROPERTY _artifactory_fetch_message_printed)
    if(NOT message_printed)
        # We are about to do network IO, which can hang for a while if
        # something is wrong, so we need to keep the user informed.
        message(STATUS "Looking for prebuilt artifacts on Artifactory server:")
        set_property(GLOBAL PROPERTY _artifactory_fetch_message_printed 1)
    endif()

    # Fetch the artifact with `art`. It's possible to this with Maven...
    #
    #    https://maven.apache.org/plugins/maven-dependency-plugin/get-mojo.html
    #
    # ...but this only works if you know the structure of the artifact in
    # advance (as you need to specify all classifiers and extensions up front),
    # and it always checks the Maven central repository, and it always puts the
    # results in ~/.m2.

    # Due to CMake's weird escaping rules we can't actually pass this string to
    # execute_process(), you need to copy and paste it.
    set(artifactory_command
        # We pass --split-count=0 to work around https://github.com/JFrogDev/artifactory-cli-go/issues/7
        "${ARTIFACTORY_CLI} download ${ARTIFACT_REPO}${remote_path}/${remote_filename} \"${extra_args}\" --split-count=0")
    file(APPEND ${ARTIFACTORY_CACHE_DIR}/artifactory.log "Running ${artifactory_command}\n")

    execute_process(
        COMMAND
            ${ARTIFACTORY_CLI} download ${ARTIFACT_REPO}${remote_path}/${remote_filename} "${extra_args}" --split-count=0
        OUTPUT_VARIABLE
            download_output
        ERROR_VARIABLE
            download_output
        RESULT_VARIABLE
            download_result
        WORKING_DIRECTORY
            ${ARTIFACTORY_CACHE_DIR}
    )

    file(APPEND ${ARTIFACTORY_CACHE_DIR}/artifactory.log "Attempt to download ${remote_path}/${remote_filename}")
    file(APPEND ${ARTIFACTORY_CACHE_DIR}/artifactory.log "${download_output}\n")

    if(NOT download_result EQUAL 0)
        message(FATAL_ERROR
            "Error running Artifactory CLI ${ARTIFACTORY_CLI}: "
            "${download_result}.\n"
            "Command was: ${artifactory_command}\n"
            "Output: ${download_output}.")
    endif()

    # FIXME: what happens if you can't contact the Artifactory server (no network or whatever?)

    # The remote_filename probably contain globs. The -SNAPSHOT versioning
    # feature is normally used, so if there are multiple matching snapshot
    # builds for a given artifact, `art` will download all of them.
    #
    # It's highly recommended to filter the SNAPSHOT artifacts by source commit
    # SHA1, and there /should/ be only one build per commit, but we must handle
    # other cases.
    #
    # Each individual Maven artifact can consist of multiple files, too, with
    # different classifiers and extensions. So here we calculate the remote
    # filename again, but with classifier set to "" instead of "*". This
    # produces a filename pattern that will only match the *main* artifact,
    # which means we will now be counting the number of artifacts fetched,
    # rather than the number of total files.
    _artifactory_calculate_path_and_filename(
        main_remote_path main_remote_filename ${ARTIFACT_GROUP} ${ARTIFACT_NAME} ${ARTIFACT_VERSION} "" "*" TRUE
    )
    file(GLOB artifact_main_files ${ARTIFACTORY_CACHE_DIR}/${remote_path}/${main_remote_filename})
    list(LENGTH artifact_main_files n_artifacts)

    if(n_artifacts EQUAL 0)
        # No artifacts for you!
        message(STATUS "    - No prebuilt artifacts found for ${ARTIFACT_NAME}")
        unset(${result_var})
    else()
        # If there are several to choose from, pick the one that is
        # alphanumerically last, because that will hopefully be the latest
        # build.
        list(SORT artifact_main_files)
        list(GET artifact_main_files -1 latest_artifact_main_file)

        get_filename_component(latest_artifact_main_file_name ${latest_artifact_main_file} NAME)

        # Now everything gets even more complicated.
        # FIXME: THIS NEEDS EXTENSIVE TESTING! Does it work without -SNAPSHOT?
        #
        # We need to extract the actual version number of the latest artifact,
        # so we can find the other files that make up that artifact.
        #
        # First, we calculate how far through the filename the word -SNAPSHOT
        # occurs (base_filename_length).
        string(REGEX REPLACE "-SNAPSHOT$" "" version_no_snapshot ${ARTIFACT_VERSION})
        _artifactory_calculate_path_and_filename(
            base_path base_filename ${ARTIFACT_GROUP} ${ARTIFACT_NAME} ${version_no_snapshot} "" "" TRUE
        )
        string(LENGTH ${base_filename} base_filename_length)
        #message("base filename is ${base_filename}, length ${base_filename_length}")

        # Now we slice the real filename from that point, and look for the last
        # occurance of: "-", followed by one more digits, followed by "." or
        # the end of the string.
        #
        # This *should* tell us where the extension starts. The only way it can
        # break is if the file's extension contains '-1' or something, which
        # is fairly unlikely (and might also confuse Artifactory).
        #
        # A simpler approach would be to get the caller to tell us the expected
        # extension of the main artifact. Maybe we should do that instead :)
        string(SUBSTRING ${latest_artifact_main_file_name} ${base_filename_length} -1 latest_artifact_main_file_tail)
        #message("tail is ${latest_artifact_main_file_tail}")
        string(REGEX MATCH "(.*-[0-9]+)(\.|$)" snapshot_junk ${latest_artifact_main_file_tail})
        set(snapshot_version ${CMAKE_MATCH_1})

        #message("Got snapshot version: ${snapshot_version}")
        string(REGEX REPLACE "-SNAPSHOT$" "${snapshot_version}" latest_artifact_version ${ARTIFACT_VERSION})

        # Now we can calculate a pattern that matches all the files that make
        # up the latest version of the artifact that we want. If you're still
        # alive.
        _artifactory_calculate_path_and_filename(
            latest_path latest_pattern ${ARTIFACT_GROUP} ${ARTIFACT_NAME} ${latest_artifact_version} "" "" FALSE
        )
        # message("Latest pattern: ${latest_pattern}")

        file(GLOB latest_artifact_files ${ARTIFACTORY_CACHE_DIR}/${remote_path}/${latest_pattern}*)

        # It's important to note that artifactory_fetch() and
        # artifactory_add_artifact() don't *force* the underlying build
        # rule to use a prebuilt artifact. So the word "suggesting" is used
        # deliberately here -- at this point, we don't want to imply that the
        # artifact will actually be used, because we can't know for sure.
        if(n_artifacts EQUAL 1)
            message(STATUS "    - Found prebuilt artifact for ${ARTIFACT_NAME}")
            message(STATUS "      Suggesting: ${latest_artifact_main_file_name}")
            set(${result_var} ${latest_artifact_files} PARENT_SCOPE)
        else()
            # This situation should not occur in theory, but there's no
            # mechanism to prevent uploading multiple builds of the exact same
            # source code, and it shouldn't actually cause anything to break.
            message(STATUS "    - Found ${n_artifacts} prebuilt artifacts for ${ARTIFACT_NAME}")
            message(STATUS "      Suggesting: ${latest_artifact_main_file_name}")
            set(${result_var} ${latest_artifact_files} PARENT_SCOPE)
            #message("Result: ${latest_artifact_files}")
        endif()
    endif()
endfunction()

# ::
#
#    artifactory_upload(<name>
#                       LOCAL_DIRECTORY <directory>
#                       LOCAL_TARGET <target>
#                       REPO <repo>
#                       GROUP <group-id>
#                       NAME <artifact-id>
#                       VERSION <version>
#                       [NO_AUTOGENERATED_POM]
#                       [PROPERTIES <prop1> <value1> <prop2> <value2> ...])
#
# Adds a target called <name> that uploads an artifact to the Artifactory repo
# cache, if the ARTIFACTORY_SUBMIT option is ON.
#
# The target will not depend on the LOCAL_TARGET. The user of the build system
# needs to ensure that the target is built before trying to upload artifacts.
# If it is not, nothing will be uploaded for that target. This lack of a
# dependency is intentional. If there was a dependency, then the overall
# `artifactory-submit` target would effectively depend on the `all` target,
# which is often annoying. This way, you can build a subset of the artifacts,
# then run `make artifactory-submit` to submit whatever was built.
#
# This command does not check if an artifact with the same name already exists
# -- if one does, it will be overwritten, if the Artifactory permissions allow
# that. If the version string ends with -SNAPSHOT, and the remote path follows
# Maven artifact path rules, then Artifactory will replace -SNAPSHOT with the
# a unique timestamp & build number string in the remote filename.
#
# It assumes that the `art` commandline tool has been configured with the
# correct credentials using the `art config` command.
#
# Rather than taking the filenames of the artifact's files to upload, it takes
# the name of the directory that should contain the artifact files once
# <target> has been created. It assumes the filenames are correct.
#
# It calculates the target path automatically based on the NAME, VERSION,
# and GROUP arguments. Only the Maven2 repository layout is supported at
# present.
#
# Unless NO_AUTOGENERATED_POM is set, a Maven-compatible POM XML file is
# generated if needed. This ensures that Artifactory snapshot repositories work
# correctly.
#
# Example:
#    artifactory_upload(
#        artifactory-upload-foo
#        LOCAL_TARGET foo
#        LOCAL_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/artifact-output
#        REPO com.example
#        GROUP com.example.libraries
#        NAME foo
#        VERSION 1.2.8-SNAPSHOT
#        UPLOAD_VERSION 1.2.8-20160107.130600_1234
#        PROPERTIES
#            vcs.revision "${FOO_COMMIT_SHA1}")
#
# In this case, the local directory should contain a file named:
#
#   foo-1.2.8-SNAPSHOT.tar.gz
#
function(artifactory_upload name)
    if(NOT ARTIFACTORY_SUBMIT)
        return()
    endif()

    set(options NO_AUTOGENERATED_POM)
    set(one_value_keywords GROUP LOCAL_DIRECTORY LOCAL_TARGET NAME REPO VERSION UPLOAD_VERSION)
    set(multi_value_keywords PROPERTIES)
    cmake_parse_arguments(ARTIFACT "${options}" "${one_value_keywords}" "${multi_value_keywords}" ${ARGN})

    ensure_all_arguments_parsed(artifactory_upload "${ARTIFACT_UNPARSED_ARGUMENTS}")
    require_arguments(artifactory_upload ARTIFACT GROUP LOCAL_DIRECTORY LOCAL_TARGET NAME REPO VERSION UPLOAD_VERSION)
    _artifactory_check_version(${ARTIFACT_VERSION})

    set(extra_args)

    if(ARTIFACT_PROPERTIES)
        _artifactory_parse_properties(props_string "${ARTIFACT_PROPERTIES}")
        foreach(property ${props_string})
            list(APPEND extra_args --property ${property})
        endforeach()
    endif()

    if(ARTIFACT_NO_AUTOGENERATED_POM)
        list(APPEND extra_args --no-autogenerated-pom)
    endif()

    add_custom_target(${name}
        # This deliberately does not depend on ${ARTIFACT_LOCAL_TARGET}.
        COMMAND
            ${CMAKE_SOURCE_DIR}/support/scripts/artifactory-upload
                ${ARTIFACT_REPO}
                ${ARTIFACT_GROUP}
                ${ARTIFACT_NAME}
                ${ARTIFACT_VERSION}
                ${ARTIFACT_UPLOAD_VERSION}
                ${ARTIFACT_LOCAL_DIRECTORY}/*
                ${extra_args}
                --artifactory-cli=${ARTIFACTORY_CLI}
                --ignore-missing
        COMMENT
            "Uploading ${ARTIFACT_LOCAL_TARGET} artifacts to ${ARTIFACT_REPO}"
        VERBATIM
    )
endfunction()

function(_artifactory_parse_properties result_var properties)
    list(LENGTH properties properties_length)

    math(EXPR properties_even "${properties_length} % 2")
    if(properties_even)
        message(FATAL_ERROR "Invalid Artifactory properties list: ${properties}")
    endif()

    math(EXPR properties_length "${properties_length} - 1")
    foreach(i RANGE 0 ${properties_length} 2)
        math(EXPR i_1 "${i} + 1")

        list(GET properties ${i} prop_name)
        list(GET properties ${i_1} prop_value)

        list(APPEND result "${prop_name}=${prop_value}")
    endforeach()

    set(${result_var} ${result} PARENT_SCOPE)
endfunction()

function(_artifactory_calculate_path_and_filename path_var filename_var group name version classifier extension snapshot_becomes_wildcard)
    # Filename follows the Maven path format:
    #   [orgPath]/[module]/[baseRev](-[folderItegRev])/[module]-[baseRev](-[fileItegRev])(-[classifier]).([ext])

    string(REPLACE . / group_path ${group})
    if(classifier)
        set(classifier_section -${classifier})
    else()
        set(classifier_section)
    endif()

    if(extension)
        set(extension_section .${extension})
    else()
        set(extension_section)
    endif()

    set(folder_version ${version})
    if(snapshot_becomes_wildcard)
        string(REGEX REPLACE -SNAPSHOT$ -* file_version ${version})
    else()
        set(file_version ${version})
    endif()

    set(${path_var} /${group_path}/${name}/${folder_version} PARENT_SCOPE)
    set(${filename_var} ${name}-${file_version}${classifier_section}${extension_section} PARENT_SCOPE)
endfunction()

function(_artifactory_check_version version_string)
    # Ensure there are no special characters that would break things
    set(invalid_chars "*/[]\\")

    if(${version_string} MATCHES "[${invalid_chars}]?")
        message(FATAL_ERROR
            "Version string '${version_string}' contains invalid characters. "
            "The following characters are not allowed in Artifactory version "
            "strings: ${invalid_chars}")
    endif()
endfunction()
