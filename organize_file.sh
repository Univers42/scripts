# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    organize_file.sh                                   :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: dlesieur <dlesieur@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/05/18 21:19:26 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:26 by dlesieur         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

#!/bin/bash

# Move every regular file in TARGET_DIR into a subdirectory named after its
# extension. Defaults to the current directory.
TARGET_DIR="${1:-$PWD}"
for file in "$TARGET_DIR"/*; do
    [ -e "$file" ] || continue
    [ -d "$file" ] && continue
    EXT="${file##*.}"
    mkdir -p "$TARGET_DIR/$EXT"
    mv "$file" "$TARGET_DIR/$EXT"
done
echo "Files organized by extension."
