# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    register_shell.sh                                  :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: dlesieur <dlesieur@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/05/18 21:19:26 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:26 by dlesieur         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

#!/bin/sh

SHELL_PATH="/usr/bin/hellish"

echo "Registering shell..."

if ! grep -qx "$SHELL_PATH" /etc/shells; then
	echo "$SHELL_PATH" | sudo tee -a /etc/shells > /dev/null
else
	echo "Shell already registered"
fi

echo "Setting default shell for $USER"
chsh -s "$SHELL_PATH"