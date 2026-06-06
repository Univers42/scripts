# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    search_and_replace.sh                              :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: dlesieur <dlesieur@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/05/18 21:19:26 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:26 by dlesieur         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

#!/bin/bash

EXT="$1"
SEARCH="$2"
REPLACE="$3"

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <extension> <search_pattern> <replace_string>"
    exit 1
fi

find . -type f -name "*$EXT" | while read -r file; do
    sed -i "s/$SEARCH/$REPLACE/g" "$file"
    echo "Updated: $file"
done
