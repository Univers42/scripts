# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    template.sh                                        :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: dlesieur <dlesieur@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/05/18 21:19:26 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:26 by dlesieur         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

#!/bin/sh

# Create a C source or header file from a template, chosen by the extension of
# each filename passed as an argument. With no arguments it does nothing.
template() {
    file="$1"
    extension="${file##*.}"
    if [ "$extension" = "c" ]; then
        cat <<'EOF' > "$file"
#include <stdio.h>
#include <stdlib.h>

void function(void)
{
    return;
}

int main(void)
{
    return (0);
}
EOF
        echo "C template written to $file"
    elif [ "$extension" = "h" ]; then
        cat <<'EOF' > "$file"
#ifndef _H
# define _H

/* define your macros here */

#endif
EOF
        echo "Header template written to $file"
    else
        echo "template: unknown extension '$extension' (use .c or .h)" >&2
    fi
}

# Loop through all provided arguments
for file in "$@"; do
    template "$file"
done
