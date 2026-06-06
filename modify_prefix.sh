# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    modify_prefix.sh                                   :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: dlesieur <dlesieur@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/05/18 21:19:26 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:26 by dlesieur         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

#!/bin/bash
find . -type f -not -name "ft_*" -name "*.c" -exec bash -c '
  for file; do
    filename=$(basename "$file")
    if [[ "$filename" != ft_* ]]; then
      mv "$file" "$(dirname "$file")/ft_$filename"
    fi
  done
' bash {} +
