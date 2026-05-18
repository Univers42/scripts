# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    organize_file.sh                                   :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: dlesieur <dlesieur@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/05/18 21:19:31 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:31 by dlesieur         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

#!/bin/bash 
TARGET_DIR=${1:-$(PWD)}
for file in "$TARGET_DIR"/*;do
    EXT="${file##*.}"
    mdkir -p "$TARGET_DIR/$EXT"
    mv "$file" "$TARGET_DIR/$EXT"
fi
done
echo "Files organized by extension."