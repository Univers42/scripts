# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    download_manager.sh                                :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: dlesieur <dlesieur@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/05/18 21:19:22 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:22 by dlesieur         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

#!/bin/bash
# Download Manager

URL_FILE=${1:-urls.txt}
DEST_DIR=${2:-downloads}

mkdir -p "$DEST_DIR"
while read -r URL; do
  wget -P "$DEST_DIR" "$URL"
done < "$URL_FILE"
echo "Downloads completed."
