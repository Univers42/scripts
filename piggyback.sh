# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    piggyback.sh                                       :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: dlesieur <dlesieur@student.42.fr>          +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
<<<<<<< HEAD
#    Created: 2026/05/18 21:19:26 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:26 by dlesieur         ###   ########.fr        #
=======
#    Created: 2026/05/18 21:19:31 by dlesieur          #+#    #+#              #
#    Updated: 2026/05/18 21:19:31 by dlesieur         ###   ########.fr        #
>>>>>>> tmp/detached-a3c30f43
#                                                                              #
# **************************************************************************** #

#/bin/bash

# For example, in .git/hooks/post-commit:

git pull origin develop
echo "$(date): $(git log -1 --pretty=%B)" >> monitor_log.txt