# Copyright 2016 Raumfeld
#
# Distributed under the OSI-approved BSD License (the "License");
# see accompanying file LICENSE for details.
#
# This software is distributed WITHOUT ANY WARRANTY; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the License for more information.

# ::
#
#    find_artifact_file(<result_var> <pattern>)
#
# Looks for a single file matching <pattern>.
#
# If <pattern> is a relative path it is interpreted relative to
# ${CMAKE_CURRENT_BINARY_DIR}.
#
# If a file is found, the <result_var> variable is set to point to its
# location. If <pattern> is empty and/or no files are found, <result_var> is
# unset.
#
# If multiple matching files are found, this is reported as a fatal error.
# There is no way of guessing which one is the correct one, and it could
# produce very confusing errors if we return an artifact that is sublty
# incompatible with the current build.
#
# When dealing with artifacts made up of more than one file. you must ensure
# that the name of the main artifact file can't be confused with any
# supplementary artifact files. If your main artifact pattern is
# 'foo-1.0*.tar.gz', but you also have a file named 'foo-1.0-tools.tar.gz',
# the first glob pattern will match both files and cause an error. You can work
# around this by giving the main artifact a special extension, e.g.
# 'foo-1.0.foo.tar.gz'.
#
function(find_artifact_file result_var pattern)
    if(NOT pattern)
        unset(${result_var} PARENT_SCOPE)
    else()
        if(NOT IS_ABSOLUTE ${pattern})
            set(pattern ${CMAKE_CURRENT_BINARY_DIR}/${pattern})
        endif()

        file(GLOB files ${pattern})

        list(LENGTH files n_files)

        if(n_files EQUAL 0)
            unset(${result_var} PARENT_SCOPE)
        elseif(n_files EQUAL 1)
            set(${result_var} ${files} PARENT_SCOPE)
        else()
            message(FATAL_ERROR
                    "Multiple files found matching artifact pattern:\n"
                    "${pattern}\nPlease remove all stale artifacts.")
        endif()
    endif()
endfunction()
