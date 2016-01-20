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
#    default_value(<varname> <value>)
#
# If <varname> is unset, sets <varname> to <value>.
#
macro(default_value varname value)
    if(NOT ${varname})
        set(${varname} ${value})
    endif()
endmacro()
