# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    piggyback.sh                                       :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: dlesieur <dlesieur@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/05/18 21:19:26 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:26 by dlesieur         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

#/bin/bash

# For example, in .git/hooks/post-commit:

git pull origin develop
echo "$(date): $(git log -1 --pretty=%B)" >> monitor_log.txt
